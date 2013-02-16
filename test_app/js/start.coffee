###*
  @fileoverview App start.
###

goog.provide 'app.start'

goog.require 'app.Employee'

###*
  @param {Object} data JSON from server
###
app.start = (data) ->
  employee = new app.Employee 'Joe'
  alert employee

goog.exportSymbol 'app.start', app.start