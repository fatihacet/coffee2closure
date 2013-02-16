goog.provide 'app.Employee'

goog.require 'app.Person'

class app.Employee extends app.Person

  ###*
    @param {string} name
    @constructor
    @extends {app.Person}
  ###
  constructor: (name) ->
    super name