import 'package:flutter/material.dart';

class LeadsFilterHeader extends StatelessWidget {
  final String role;
  final String? selectedBranch;
  final List<String> availableBranches;
  final ValueChanged<String?> onBranchChanged;
  final String? selectedUser;
  final List<Map<String, dynamic>> availableUsers;
  final ValueChanged<String?> onUserChanged;
  final String selectedStatus;
  final List<String> statusOptions;
  final ValueChanged<String?> onStatusChanged;
  final String selectedPriority;
  final List<String> priorityOptions;
  final ValueChanged<String?> onPriorityChanged;
  final bool sortAscending;
  final ValueChanged<bool?> onSortChanged;
  final String selectedSource;
  final List<String> sourceOptions;
  final ValueChanged<String?> onSourceChanged;

  const LeadsFilterHeader({
    super.key,
    required this.role,
    required this.selectedBranch,
    required this.availableBranches,
    required this.onBranchChanged,
    required this.selectedUser,
    required this.availableUsers,
    required this.onUserChanged,
    required this.selectedStatus,
    required this.statusOptions,
    required this.onStatusChanged,
    required this.selectedPriority,
    required this.priorityOptions,
    required this.onPriorityChanged,
    required this.sortAscending,
    required this.onSortChanged,
    required this.selectedSource,
    required this.sourceOptions,
    required this.onSourceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isAdminLike = role == 'admin' || role == 'Sync Head' || role == 'sync_head';
    final isManagerLike = role == 'manager' || role == 'asst_manager';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: isAdminLike
          ? Column(
              children: [
                Row(
                  children: [
                    Flexible(
                      flex: 1,
                      child: SizedBox(
                        height: 36,
                        child: DropdownButtonFormField<String>(
                          value: selectedBranch,
                          items: availableBranches
                              .map((branch) => DropdownMenuItem(
                                    value: branch,
                                    child: Text(
                                      branch,
                                      style: const TextStyle(fontSize: 9),
                                    ),
                                  ))
                              .toList(),
                          onChanged: onBranchChanged,
                          decoration: InputDecoration(
                            labelText: 'Branch',
                            labelStyle: const TextStyle(fontSize: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color.fromARGB(255, 229, 237, 229),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                          style: const TextStyle(fontSize: 10, color: Colors.black),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.arrow_drop_down, size: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      flex: 1,
                      child: SizedBox(
                        height: 36,
                        child: DropdownButtonFormField<String>(
                          value: selectedUser,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('All Users', style: TextStyle(fontSize: 9)),
                            ),
                            ...availableUsers.map((user) => DropdownMenuItem(
                                  value: user['id'],
                                  child: Text(
                                    user['username'],
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                )),
                          ],
                          onChanged: onUserChanged,
                          decoration: InputDecoration(
                            labelText: 'User',
                            labelStyle: const TextStyle(fontSize: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color.fromARGB(255, 229, 237, 229),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 1, vertical: 10),
                          ),
                          style: const TextStyle(fontSize: 8, color: Colors.black),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.arrow_drop_down, size: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      flex: 1,
                      child: SizedBox(
                        height: 36,
                        child: DropdownButtonFormField<String>(
                          value: selectedStatus,
                          items: statusOptions.map((status) {
                            return DropdownMenuItem<String>(
                              value: status,
                              child: Text(
                                status,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }).toList(),
                          onChanged: onStatusChanged,
                          decoration: InputDecoration(
                            labelText: 'Status',
                            labelStyle: const TextStyle(fontSize: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color.fromARGB(255, 229, 237, 229),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                          style: const TextStyle(fontSize: 10, color: Colors.black),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.arrow_drop_down, size: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      flex: 1,
                      child: SizedBox(
                        height: 36,
                        child: DropdownButtonFormField<String>(
                          value: selectedPriority,
                          items: priorityOptions.map((priority) {
                            return DropdownMenuItem<String>(
                              value: priority,
                              child: Text(
                                priority,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }).toList(),
                          onChanged: onPriorityChanged,
                          decoration: InputDecoration(
                            labelText: 'Priority',
                            labelStyle: const TextStyle(fontSize: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color.fromARGB(255, 229, 237, 229),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                          style: const TextStyle(fontSize: 10, color: Colors.black),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.arrow_drop_down, size: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      flex: 1,
                      child: SizedBox(
                        height: 36,
                        child: DropdownButtonFormField<bool>(
                          value: sortAscending,
                          items: const [
                            DropdownMenuItem(
                              value: false,
                              child: Text('Newest', style: TextStyle(fontSize: 10)),
                            ),
                            DropdownMenuItem(
                              value: true,
                              child: Text('Oldest', style: TextStyle(fontSize: 10)),
                            ),
                          ],
                          onChanged: onSortChanged,
                          decoration: InputDecoration(
                            labelText: 'Sort',
                            labelStyle: const TextStyle(fontSize: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color.fromARGB(255, 229, 237, 229),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                          style: const TextStyle(fontSize: 10, color: Colors.black),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.arrow_drop_down, size: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      flex: 1,
                      child: SizedBox(
                        height: 36,
                        child: DropdownButtonFormField<String>(
                          value: selectedSource,
                          items: sourceOptions.map((s) {
                            return DropdownMenuItem<String>(
                              value: s,
                              child: Text(s, style: const TextStyle(fontSize: 10)),
                            );
                          }).toList(),
                          onChanged: onSourceChanged,
                          decoration: InputDecoration(
                            labelText: 'Source',
                            labelStyle: const TextStyle(fontSize: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color.fromARGB(255, 229, 237, 229),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          ),
                          style: const TextStyle(fontSize: 10, color: Colors.black),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.arrow_drop_down, size: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : isManagerLike
              ? Column(
                  children: [
                    Row(
                      children: [
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<String>(
                              value: selectedUser,
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('All Users', style: TextStyle(fontSize: 9)),
                                ),
                                ...availableUsers.map((user) => DropdownMenuItem(
                                      value: user['id'],
                                      child: Text(
                                        user['username'],
                                        style: const TextStyle(fontSize: 9),
                                      ),
                                    )),
                              ],
                              onChanged: onUserChanged,
                              decoration: InputDecoration(
                                labelText: 'User',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 1, vertical: 10),
                              ),
                              style: const TextStyle(fontSize: 8, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<String>(
                              value: selectedStatus,
                              items: statusOptions.map((status) {
                                return DropdownMenuItem<String>(
                                  value: status,
                                  child: Text(
                                    status,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              }).toList(),
                              onChanged: onStatusChanged,
                              decoration: InputDecoration(
                                labelText: 'Status',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<String>(
                              value: selectedPriority,
                              items: priorityOptions.map((priority) {
                                return DropdownMenuItem<String>(
                                  value: priority,
                                  child: Text(
                                    priority,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              }).toList(),
                              onChanged: onPriorityChanged,
                              decoration: InputDecoration(
                                labelText: 'Priority',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<bool>(
                              value: sortAscending,
                              items: const [
                                DropdownMenuItem(
                                  value: false,
                                  child: Text('Newest', style: TextStyle(fontSize: 10)),
                                ),
                                DropdownMenuItem(
                                  value: true,
                                  child: Text('Oldest', style: TextStyle(fontSize: 10)),
                                ),
                              ],
                              onChanged: onSortChanged,
                              decoration: InputDecoration(
                                labelText: 'Sort',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<String>(
                              value: selectedSource,
                              items: sourceOptions.map((s) {
                                return DropdownMenuItem<String>(
                                  value: s,
                                  child: Text(s, style: const TextStyle(fontSize: 10)),
                                );
                              }).toList(),
                              onChanged: onSourceChanged,
                              decoration: InputDecoration(
                                labelText: 'Source',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Column(
                  children: [
                    Row(
                      children: [
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<String>(
                              value: selectedStatus,
                              items: statusOptions.map((status) {
                                return DropdownMenuItem<String>(
                                  value: status,
                                  child: Text(
                                    status,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              }).toList(),
                              onChanged: onStatusChanged,
                              decoration: InputDecoration(
                                labelText: 'Status',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<String>(
                              value: selectedPriority,
                              items: priorityOptions.map((priority) {
                                return DropdownMenuItem<String>(
                                  value: priority,
                                  child: Text(
                                    priority,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              }).toList(),
                              onChanged: onPriorityChanged,
                              decoration: InputDecoration(
                                labelText: 'Priority',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<bool>(
                              value: sortAscending,
                              items: const [
                                DropdownMenuItem(
                                  value: false,
                                  child: Text('Newest', style: TextStyle(fontSize: 10)),
                                ),
                                DropdownMenuItem(
                                  value: true,
                                  child: Text('Oldest', style: TextStyle(fontSize: 10)),
                                ),
                              ],
                              onChanged: onSortChanged,
                              decoration: InputDecoration(
                                labelText: 'Sort',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: DropdownButtonFormField<String>(
                              value: selectedSource,
                              items: sourceOptions.map((s) {
                                return DropdownMenuItem<String>(
                                  value: s,
                                  child: Text(s, style: const TextStyle(fontSize: 10)),
                                );
                              }).toList(),
                              onChanged: onSourceChanged,
                              decoration: InputDecoration(
                                labelText: 'Source',
                                labelStyle: const TextStyle(fontSize: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: const Color.fromARGB(255, 229, 237, 229),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              ),
                              style: const TextStyle(fontSize: 10, color: Colors.black),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}
