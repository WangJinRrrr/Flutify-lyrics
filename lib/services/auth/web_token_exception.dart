/// The Web token endpoint rejected a request. A 403 alone does not establish
/// that the user's login expired; do not include its response body in logs.
class WebTokenHttpException extends StateError {
  WebTokenHttpException(this.statusCode)
    : super('铸造 Web token 失败：HTTP $statusCode');

  final int statusCode;
}

class WebSignInRequiredException extends StateError {
  WebSignInRequiredException() : super('缺少 sp_dc（需先完成 Web 登录）');
}
