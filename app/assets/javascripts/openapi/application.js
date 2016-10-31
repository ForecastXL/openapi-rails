//= require 'openapi/lib/object-assign-pollyfill.js'
//= require 'openapi/lib/jquery-1.8.0.min.js'
//= require 'openapi/lib/jquery.slideto.min.js'
//= require 'openapi/lib/jquery.wiggle.min.js'
//= require 'openapi/lib/jquery.ba-bbq.min.js'
//= require 'openapi/lib/handlebars-4.0.5.js'
//= require 'openapi/lib/lodash.min.js'
//= require 'openapi/lib/backbone-min.js'
//= require 'openapi/swagger-ui.js'
//= require 'openapi/lib/highlight.9.1.0.pack.js'
//= require 'openapi/lib/highlight.9.1.0.pack_extended.js'
//= require 'openapi/lib/jsoneditor.min.js'
//= require 'openapi/lib/marked.js'
//= require 'openapi/lib/swagger-oauth.js'

var indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

$(function() {
  var log, url;
  $('#input_spec').on('change', function(e) {
    var specUrl;
    specUrl = $(this).val();
    $('#input_baseUrl').val(specUrl);
    swaggerUi.headerView.showCustom();
    return window.location.hash = "/url=" + specUrl;
  });
  url = window.location.hash.match(/url=([^&]+)/);
  if (url && url.length > 1) {
    url = decodeURIComponent(url[1]);
    $('#input_spec').val(url);
  } else {
    url = $('#input_baseUrl').val();
  }
  hljs.configure({
    highlightSizeThreshold: 5000
  });
  if (window.SwaggerTranslator) {
    window.SwaggerTranslator.translate();
  }
  window.swaggerUi = new SwaggerUi({
    url: url,
    dom_id: 'swagger-ui-container',
    supportedSubmitMethods: ['get', 'post', 'put', 'delete', 'patch'],
    onComplete: function(swaggerApi, swaggerUi) {
      if (window.SwaggerTranslator) {
        return window.SwaggerTranslator.translate();
      }
    },
    onFailure: function(data) {
      return log('Unable to Load SwaggerUI');
    },
    docExpansion: 'none',
    jsonEditor: false,
    defaultModelRendering: 'schema',
    showRequestHeaders: true
  });
  window.swaggerUi.load();
  return log = function() {
    if (indexOf.call(window, 'console') >= 0) {
      return console.log.apply(console, arguments);
    }
  };
});
