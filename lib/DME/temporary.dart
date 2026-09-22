import 'package:flutter/material.dart';
import 'package:mtcsync/DME/Misc/dme_config.dart';

class DmeCustomerTypeFixer {
  /// Fixes customer types in `dme_customer_branches` for customers who have REGULAR (id 2)
  /// and another customer type in the same branch in their sales records.
  /// Sets their `customer_type_id` in `dme_customer_branches` to the latest customer_type_id from `dme_sales`.
  static Future<Map<String, dynamic>> fixCustomerTypesForRegularAndOther({
    required Function(String log) onLog,
    required Function(double progress, String status) onProgress,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      throw Exception('Supabase client not initialized');
    }

    onLog('Starting customer type reconciliation for customers with REGULAR and another type in the same branch...');
    onProgress(0.05, 'Fetching sales data...');

    // 1. Fetch all sales with customer_id, purchased_branch, customer_type_id, date
    // Note: Supabase PostgREST default max limit per request is 1000 rows.
    const int pageSize = 1000;
    int offset = 0;
    bool hasMore = true;
    final List<Map<String, dynamic>> allSales = [];

    while (hasMore) {
      final res = await client
          .from('dme_sales')
          .select('customer_id, purchased_branch, customer_type_id, date')
          .not('customer_id', 'is', null)
          .not('purchased_branch', 'is', null)
          .not('customer_type_id', 'is', null)
          .range(offset, offset + pageSize - 1);

      final list = res as List;
      for (var item in list) {
        allSales.add(Map<String, dynamic>.from(item));
      }

      if (list.isEmpty || list.length < pageSize) {
        hasMore = false;
      } else {
        offset += list.length;
      }
      onProgress(0.1 + (allSales.length / 50000).clamp(0.0, 0.3), 'Fetched ${allSales.length} sales records...');
    }

    onLog('✓ Fetched ${allSales.length} total sales records');
    onProgress(0.45, 'Analyzing customer sales by branch...');

    // 2. Group sales by key: "${customerId}_${branchId}"
    // Track set of customer types and the latest sale info (date + type)
    final Map<String, Set<int>> typesByKey = {};
    final Map<String, Map<String, dynamic>> latestSaleByKey = {};

    for (var sale in allSales) {
      final cId = int.tryParse(sale['customer_id']?.toString() ?? '');
      final bId = int.tryParse(sale['purchased_branch']?.toString() ?? '');
      final tId = int.tryParse(sale['customer_type_id']?.toString() ?? '');
      final dateStr = sale['date']?.toString() ?? '';

      if (cId == null || bId == null || tId == null) continue;
      final key = '${cId}_$bId';

      typesByKey.putIfAbsent(key, () => <int>{}).add(tId);

      final saleDate = DateTime.tryParse(dateStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final currentLatest = latestSaleByKey[key];
      if (currentLatest == null) {
        latestSaleByKey[key] = {
          'customer_id': cId,
          'branch_id': bId,
          'customer_type_id': tId,
          'date': saleDate,
        };
      } else {
        final currentDate = currentLatest['date'] as DateTime;
        if (saleDate.isAfter(currentDate)) {
          latestSaleByKey[key] = {
            'customer_id': cId,
            'branch_id': bId,
            'customer_type_id': tId,
            'date': saleDate,
          };
        }
      }
    }

    // 3. Filter strictly for customer-branch keys that have REGULAR (typeId 2) AND another type
    final List<Map<String, dynamic>> targetsToUpdate = [];
    int totalIdentified = 0;

    for (var entry in typesByKey.entries) {
      final key = entry.key;
      final types = entry.value;

      // Check condition: Must have REGULAR (id 2) AND another type (!= 2) in the same branch
      final hasRegular = types.contains(2);
      final hasAnotherType = types.any((t) => t != 2);

      if (hasRegular && hasAnotherType) {
        totalIdentified++;
        final latest = latestSaleByKey[key];
        if (latest != null) {
          targetsToUpdate.add(latest);
        }
      }
    }

    onLog('Found $totalIdentified customer-branch instance(s) having both REGULAR and another customer type.');
    if (targetsToUpdate.isEmpty) {
      onProgress(1.0, 'No updates needed.');
      return {
        'total_identified': 0,
        'updated_count': 0,
      };
    }

    onProgress(0.6, 'Updating customer branches to latest customer type...');

    // 4. Update dme_customer_branches in batches
    int updatedCount = 0;
    const int updateBatchSize = 100;

    for (int i = 0; i < targetsToUpdate.length; i += updateBatchSize) {
      final chunk = targetsToUpdate.sublist(
        i,
        (i + updateBatchSize > targetsToUpdate.length) ? targetsToUpdate.length : i + updateBatchSize,
      );

      final List<Map<String, dynamic>> upsertPayload = chunk.map((item) {
        return {
          'customer_id': item['customer_id'],
          'branch_id': item['branch_id'],
          'customer_type_id': item['customer_type_id'],
        };
      }).toList();

      try {
        await client.from('dme_customer_branches').upsert(
          upsertPayload,
          onConflict: 'customer_id,branch_id',
        );
        updatedCount += chunk.length;
        onProgress(
          0.6 + (0.35 * (updatedCount / targetsToUpdate.length)),
          'Updated $updatedCount / ${targetsToUpdate.length} branch records...',
        );
      } catch (err) {
        onLog('Batch upsert error: $err. Falling back to individual updates...');
        for (var item in chunk) {
          try {
            await client
                .from('dme_customer_branches')
                .update({'customer_type_id': item['customer_type_id']})
                .eq('customer_id', item['customer_id'])
                .eq('branch_id', item['branch_id']);
            updatedCount++;
          } catch (singleErr) {
            onLog('Error updating customer ${item['customer_id']} branch ${item['branch_id']}: $singleErr');
          }
        }
      }
    }

    onProgress(1.0, 'Completed successfully!');
    onLog('✓ Successfully updated $updatedCount customer branch record(s) to their latest sales customer type.');

    return {
      'total_identified': totalIdentified,
      'updated_count': updatedCount,
    };
  }

  /// Sets communication preference to 'Whatsapp' for all customers associated with CBE branch (branch ID 2)
  static Future<Map<String, dynamic>> setCbeCustomersPreferenceToWhatsapp({
    required Function(String log) onLog,
    required Function(double progress, String status) onProgress,
  }) async {
    final client = await DmeConfig.getClient();
    if (client == null) {
      throw Exception('Supabase client not initialized');
    }

    onLog('Starting update: Setting preference to "Whatsapp" for all CBE (Coimbatore) customers...');
    onProgress(0.05, 'Identifying CBE customers...');

    final Set<int> cbeCustomerIds = {};

    // 1. Check customers whose primary_branch == 2 in dme_customers
    try {
      const int pageSize = 1000;
      int offset = 0;
      bool hasMore = true;

      while (hasMore) {
        final res = await client
            .from('dme_customers')
            .select('id')
            .eq('primary_branch', 2)
            .range(offset, offset + pageSize - 1);

        final list = res as List;
        for (var item in list) {
          final id = int.tryParse(item['id']?.toString() ?? '');
          if (id != null) cbeCustomerIds.add(id);
        }

        if (list.isEmpty || list.length < pageSize) {
          hasMore = false;
        } else {
          offset += list.length;
        }
      }
      onLog('Found ${cbeCustomerIds.length} customer(s) with primary_branch = CBE (2)');
    } catch (e) {
      onLog('Notice checking primary_branch in dme_customers: $e');
    }

    // 2. Check customers who have branch_id == 2 in dme_customer_branches
    try {
      const int pageSize = 1000;
      int offset = 0;
      bool hasMore = true;

      while (hasMore) {
        final res = await client
            .from('dme_customer_branches')
            .select('customer_id')
            .eq('branch_id', 2)
            .range(offset, offset + pageSize - 1);

        final list = res as List;
        for (var item in list) {
          final id = int.tryParse(item['customer_id']?.toString() ?? '');
          if (id != null) cbeCustomerIds.add(id);
        }

        if (list.isEmpty || list.length < pageSize) {
          hasMore = false;
        } else {
          offset += list.length;
        }
      }
      onLog('Total unique CBE customers after dme_customer_branches: ${cbeCustomerIds.length}');
    } catch (e) {
      onLog('Notice checking dme_customer_branches for CBE: $e');
    }

    // 3. Check customers who have purchased_branch == 2 in dme_sales
    try {
      const int pageSize = 1000;
      int offset = 0;
      bool hasMore = true;

      while (hasMore) {
        final res = await client
            .from('dme_sales')
            .select('customer_id')
            .eq('purchased_branch', 2)
            .range(offset, offset + pageSize - 1);

        final list = res as List;
        for (var item in list) {
          final id = int.tryParse(item['customer_id']?.toString() ?? '');
          if (id != null) cbeCustomerIds.add(id);
        }

        if (list.isEmpty || list.length < pageSize) {
          hasMore = false;
        } else {
          offset += list.length;
        }
      }
      onLog('Total unique CBE customers after dme_sales check: ${cbeCustomerIds.length}');
    } catch (e) {
      onLog('Notice checking dme_sales for CBE: $e');
    }

    if (cbeCustomerIds.isEmpty) {
      onProgress(1.0, 'No CBE customers found.');
      return {
        'total_identified': 0,
        'updated_count': 0,
      };
    }

    onProgress(0.3, 'Updating preference to "Whatsapp" for ${cbeCustomerIds.length} customer(s)...');

    // 4. Batch update dme_customers: set preference = 'Whatsapp'
    final customerIdList = cbeCustomerIds.toList();
    const int updateBatchSize = 200;
    int updatedCount = 0;

    for (int i = 0; i < customerIdList.length; i += updateBatchSize) {
      final chunk = customerIdList.sublist(
        i,
        (i + updateBatchSize > customerIdList.length) ? customerIdList.length : i + updateBatchSize,
      );

      try {
        await client
            .from('dme_customers')
            .update({
              'preference': 'Whatsapp',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .inFilter('id', chunk);

        updatedCount += chunk.length;
        onProgress(
          0.3 + (0.7 * (updatedCount / customerIdList.length)),
          'Updated $updatedCount / ${customerIdList.length} customers...',
        );
      } catch (err) {
        onLog('Error batch updating customers: $err');
      }
    }

    onProgress(1.0, 'Completed successfully!');
    onLog('✓ Successfully set preference to "Whatsapp" for $updatedCount CBE customer(s).');

    return {
      'total_identified': cbeCustomerIds.length,
      'updated_count': updatedCount,
    };
  }

  /// Show interactive dialog in UI for Customer Type Reconciliation
  static void showFixDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _CustomerTypeFixDialog(),
    );
  }

  /// Show interactive dialog in UI for CBE Whatsapp Preference Update
  static void showCbeWhatsappDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _CbeWhatsappDialog(),
    );
  }
}

class _CustomerTypeFixDialog extends StatefulWidget {
  const _CustomerTypeFixDialog();

  @override
  State<_CustomerTypeFixDialog> createState() => _CustomerTypeFixDialogState();
}

class _CustomerTypeFixDialogState extends State<_CustomerTypeFixDialog> {
  bool _isRunning = false;
  double _progress = 0.0;
  String _status = 'Ready to reconcile customer types.';
  final List<String> _logs = [];
  Map<String, dynamic>? _result;

  void _runFix() async {
    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _logs.clear();
      _result = null;
    });

    try {
      final res = await DmeCustomerTypeFixer.fixCustomerTypesForRegularAndOther(
        onLog: (msg) {
          if (mounted) {
            setState(() {
              _logs.add(msg);
            });
          }
        },
        onProgress: (p, s) {
          if (mounted) {
            setState(() {
              _progress = p;
              _status = s;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isRunning = false;
          _result = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _logs.add('❌ Error: $e');
          _status = 'Failed with error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.sync_alt_rounded, color: Color(0xFF005BAC)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Reconcile Customer Types',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This tool identifies customers who have both REGULAR and another customer type in the same branch, and sets their customer type to the latest type from sales data.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 14),
            if (_isRunning || _progress > 0) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.grey[300],
                color: const Color(0xFF005BAC),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
            ],
            if (_result != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Completed: ${_result!['updated_count']} customer branch record(s) updated to their latest customer type.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_logs.isNotEmpty) ...[
              const Text('Execution Logs:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                height: 140,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _logs.length,
                  itemBuilder: (_, idx) => Text(
                    _logs[idx],
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isRunning)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ElevatedButton.icon(
          onPressed: _isRunning ? null : _runFix,
          icon: _isRunning
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(_result != null ? 'Run Again' : 'Start Reconciliation'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF005BAC),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}

class _CbeWhatsappDialog extends StatefulWidget {
  const _CbeWhatsappDialog();

  @override
  State<_CbeWhatsappDialog> createState() => _CbeWhatsappDialogState();
}

class _CbeWhatsappDialogState extends State<_CbeWhatsappDialog> {
  bool _isRunning = false;
  double _progress = 0.0;
  String _status = 'Ready to set CBE customer preference to WhatsApp.';
  final List<String> _logs = [];
  Map<String, dynamic>? _result;

  void _runUpdate() async {
    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _logs.clear();
      _result = null;
    });

    try {
      final res = await DmeCustomerTypeFixer.setCbeCustomersPreferenceToWhatsapp(
        onLog: (msg) {
          if (mounted) {
            setState(() {
              _logs.add(msg);
            });
          }
        },
        onProgress: (p, s) {
          if (mounted) {
            setState(() {
              _progress = p;
              _status = s;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isRunning = false;
          _result = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _logs.add('❌ Error: $e');
          _status = 'Failed with error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Set CBE Customers to WhatsApp',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This tool updates all customers of CBE (Coimbatore) branch to have communication preference = "Whatsapp".',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 14),
            if (_isRunning || _progress > 0) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.grey[300],
                color: const Color(0xFF25D366),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
            ],
            if (_result != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Completed: ${_result!['updated_count']} CBE customer(s) updated to WhatsApp preference.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_logs.isNotEmpty) ...[
              const Text('Execution Logs:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                height: 140,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _logs.length,
                  itemBuilder: (_, idx) => Text(
                    _logs[idx],
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isRunning)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ElevatedButton.icon(
          onPressed: _isRunning ? null : _runUpdate,
          icon: _isRunning
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(_result != null ? 'Run Again' : 'Start Update'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}
