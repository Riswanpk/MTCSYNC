import 'package:flutter/material.dart';

class YupulseUserCardItem {
  final String username;
  final String yupulseId;
  final String email;
  final String branch;
  final String period;
  bool isSubmitted;
  bool isSelected;
  final int autoTodoDoneCount;
  final int autoCallTargetCount;
  final int autoCallDoneCount;
  final int supersaleTotal;
  final int supersaleTaken;
  final int ccLeadsCreated;
  final int salesLeadsCreated;
  bool useAutoTodo;
  bool useAutoCalling;
  bool useAutoSupersale;
  bool useAutoLeads;
  final TextEditingController supersaleTotalController;
  final TextEditingController supersaleTakenController;
  final TextEditingController ccLeadsController;
  final TextEditingController salesLeadsController;
  final TextEditingController todoController;
  final TextEditingController callTargetController;
  final TextEditingController callDoneController;
  final TextEditingController todoReasonController;
  final TextEditingController callReasonController; // Alias or primary controller for customer calling
  final TextEditingController supersaleReasonController;
  final TextEditingController leadsReasonController;

  // Backward compatible getter for existing references if any
  TextEditingController get reasonController => callReasonController;

  YupulseUserCardItem({
    required this.username,
    required this.yupulseId,
    required this.email,
    required this.branch,
    required this.period,
    required this.isSubmitted,
    required this.isSelected,
    required this.autoTodoDoneCount,
    required this.autoCallTargetCount,
    required this.autoCallDoneCount,
    this.supersaleTotal = 0,
    this.supersaleTaken = 0,
    this.ccLeadsCreated = 0,
    this.salesLeadsCreated = 0,
    required this.useAutoTodo,
    required this.useAutoCalling,
    required this.useAutoSupersale,
    required this.useAutoLeads,
    required this.supersaleTotalController,
    required this.supersaleTakenController,
    required this.ccLeadsController,
    required this.salesLeadsController,
    required this.todoController,
    required this.callTargetController,
    required this.callDoneController,
    required this.callReasonController,
    required this.todoReasonController,
    required this.supersaleReasonController,
    required this.leadsReasonController,
  });

  void dispose() {
    todoController.dispose();
    callTargetController.dispose();
    callDoneController.dispose();
    callReasonController.dispose();
    todoReasonController.dispose();
    supersaleReasonController.dispose();
    leadsReasonController.dispose();
    supersaleTotalController.dispose();
    supersaleTakenController.dispose();
    ccLeadsController.dispose();
    salesLeadsController.dispose();
  }
}
