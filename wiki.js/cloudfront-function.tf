resource "aws_cloudfront_function" "access_gate" {
  name    = "${var.environment}-wiki-access-gate"
  runtime = "cloudfront-js-2.0"
  comment = "Require secret path prefix to reach Wiki.js"
  publish = true

  code = <<-JSEOF
    var TOKEN = '${var.access_token}';
    var PREFIX = '/' + TOKEN;

    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri === PREFIX || uri.startsWith(PREFIX + '/')) {
        request.uri = uri.substring(PREFIX.length) || '/';
        return request;
      }

      return {
        statusCode: 403,
        statusDescription: 'Forbidden',
        headers: { 'content-type': { value: 'text/plain' } },
        body: '403 Forbidden'
      };
    }
  JSEOF
}
