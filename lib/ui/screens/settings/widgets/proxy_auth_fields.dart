import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../../../services/network/network_proxy.dart';

/// 手动代理的「用户名 + 密码」两个输入框（可留空，表示代理不需要认证）。
///
/// 与 [ProxyServerFields] 同一套交互：回车或输入框失焦时提交；两项都空也算有效（关闭认证），
/// 所以没有「无效」状态。只有内容与 [username] / [password] 不同时才回调 [onApply]
///（每次提交都会落盘、重配代理、清掉测试结果），离开页面时未提交的改动也会补交。
class ProxyAuthFields extends StatefulWidget {
  final String username;
  final String password;
  final void Function(String username, String password) onApply;

  const ProxyAuthFields({
    super.key,
    required this.username,
    required this.password,
    required this.onApply,
  });

  @override
  State<ProxyAuthFields> createState() => _ProxyAuthFieldsState();
}

class _ProxyAuthFieldsState extends State<ProxyAuthFields> {
  late final TextEditingController _username = TextEditingController(
    text: widget.username,
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.password,
  );
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _usernameFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
    _username.addListener(_onCredentialEdited);
    _password.addListener(_onCredentialEdited);
  }

  @override
  void didUpdateWidget(ProxyAuthFields old) {
    super.didUpdateWidget(old);
    // 外部改了值（重置偏好等）就同步进输入框；正在编辑的那一项不动，免得冲掉用户输入
    if (widget.username != old.username && !_usernameFocus.hasFocus) {
      _username.text = widget.username;
    }
    if (widget.password != old.password && !_passwordFocus.hasFocus) {
      _password.text = widget.password;
    }
  }

  @override
  void dispose() {
    // 直接关掉设置页时焦点节点随之销毁、不会触发失焦提交：未提交的改动在这里补交。
    // 此刻元素树已锁定，回调里会通知 Provider，推迟到微任务里再执行
    final username = _username.text.trim();
    final password = _password.text;
    if (_changed(username, password)) {
      final apply = widget.onApply;
      scheduleMicrotask(() => apply(username, password));
    }
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _changed(String username, String password) =>
      username != widget.username || password != widget.password;

  /// 焦点离开这一组输入框时提交（在两个框之间切换不算离开）。
  void _onFocusChange() {
    if (_usernameFocus.hasFocus || _passwordFocus.hasFocus) return;
    _submit();
  }

  /// 输入变化时刷新认证提示。
  void _onCredentialEdited() => setState(() {});

  void _submit() {
    final username = _username.text.trim();
    if (username != _username.text) _username.text = username;
    // 密码不 trim：空格密码本身合法（HTTPS 经自建隧道认证，任意字符都能带上）
    if (_changed(username, _password.text))
      widget.onApply(username, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    InputDecoration decoration(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );

    // 冒号是 Basic 认证里用户名与密码的分隔符，用户名带冒号代理必然认证失败，提前提示
    final invalidUsername = !NetworkProxy.isValidUsername(
      _username.text.trim(),
    );
    final incomplete = _username.text.trim().isEmpty != _password.text.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('proxy-username'),
                controller: _username,
                focusNode: _usernameFocus,
                decoration: decoration(l10n.settingsProxyUsernameHint),
                keyboardType: TextInputType.text,
                autocorrect: false,
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('proxy-password'),
                controller: _password,
                focusNode: _passwordFocus,
                decoration: decoration(l10n.settingsProxyPasswordHint),
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                obscureText: true,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        if (invalidUsername)
          Padding(
            key: const ValueKey('proxy-username-invalid'),
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.settingsProxyUsernameInvalid,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (incomplete)
          Padding(
            key: const ValueKey('proxy-auth-incomplete'),
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.settingsProxyAuthIncomplete,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
