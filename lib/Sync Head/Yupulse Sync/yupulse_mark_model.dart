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
  final TextEditingController todoController;
  final TextEditingController callTargetController;
  final TextEditingController callDoneController;
  final TextEditingController reasonController;

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
    required this.todoController,
    required this.callTargetController,
    required this.callDoneController,
    required this.reasonController,
  });

  void dispose() {
    todoController.dispose();
    callTargetController.dispose();
    callDoneController.dispose();
    reasonController.dispose();
  }
}
