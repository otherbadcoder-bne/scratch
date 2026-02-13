resource "aws_cloudfront_function" "access_gate" {
  name    = "${var.environment}-wiki-access-gate"
  runtime = "cloudfront-js-2.0"
  comment = "Require secret path prefix to reach Wiki.js"
  publish = true

  code = <<-JSEOF
    var TOKEN = '${var.access_token}';
    var PREFIX = '/' + TOKEN;
    var COOKIE_NAME = '__wiki_access';

    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // Knock: token in path sets a cookie and redirects to clean URL
      if (uri === PREFIX || uri.startsWith(PREFIX + '/')) {
        var destination = uri.substring(PREFIX.length) || '/';
        return {
          statusCode: 302,
          statusDescription: 'Found',
          headers: {
            'location': { value: destination },
            'cache-control': { value: 'no-store' }
          },
          cookies: {
            '__wiki_access': { value: TOKEN, attributes: 'Path=/; Secure; HttpOnly; SameSite=Strict' }
          }
        };
      }

      // Subsequent requests: check for the cookie
      var cookies = request.cookies || {};
      if (cookies[COOKIE_NAME] && cookies[COOKIE_NAME].value === TOKEN) {
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
