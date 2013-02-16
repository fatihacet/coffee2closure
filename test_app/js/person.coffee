###*
  @fileoverview
###
goog.provide 'app.Person'

class app.Person

  ###*
    @param {string} name
    @constructor
  ###
  constructor: (@name) ->
    @alertName()

  ###*
    @enum {string}
  ###
  @EventType:
    FOO: 'foo'

  ###*
    @type {string}
    @protected
  ###
  name: ''

  ###*
    @protected
  ###
  alertName: ->
    alert @name + Person.EventType.FOO