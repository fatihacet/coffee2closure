###
  @fileoverview Fix CoffeeScript compiled output for Google Closure Compiler.
  Code is beautified for easier debugging and compiled output reading.

  Issues
    CoffeeScript class declaration.
      unwrap for compiler be able to parse annotations
      change __extends to goog.inherits
      change __super__ to superClass_
      remove some mess
      ensure constructor is first after unwrap

    Remove and alias injected helpers.
      Closure Compiler needs bare code and injected methods are repeatedly
      declared in global space, which is wrong.
      __bind, __indexOf and __slice are replaced with Closure Array functions.

  Not Fixed (yet)
    Class metaprogramming possibilities, e.g. imperative code inside class
    declaration. It works, but variables are not scoped inside.
    Annotated splats.

  To Consider
    goog.scope, leverage it

###

esprima = require 'esprima'

requireGoogArray = false

###*
  @param {string} source
  @param {Object} options
    addGenerateByHeader: true
  @return {string}
###
exports.fix = fix = (source, options) ->
  requireGoogArray = false

  syntax = parse source

  # ignore nodejs for now
  isNodeJs = syntax.tokens.some (item) ->
    item.type == 'Identifier' &&
    item.value == 'exports'
  return source if isNodeJs

  tokens = prepareTokens syntax, source
  constructors = findConstructors tokens
  linesToRemove = {}

  removeInjectedCode syntax, linesToRemove
  fixClasses constructors, tokens, linesToRemove

  removeLines tokens, linesToRemove
  aliasRemovedInjectedCode tokens

  source = mergeTokens tokens

  if requireGoogArray
    source = 'goog.require(\'goog.array\');\n' + source
  if !options || options.addGenerateByHeader
    source = addGeneratedBy source
  return source

###*
  Traverse AST tree.
  @param {*}
  @param {Function} visitor Gets node. Return false to stop iteration.
  @return {boolan} false stops itesuper__
###
exports.traverse = traverse = (object, visitor) ->
  result = iterator object, (key, value) ->
    return if !value || typeof value != 'object'

    if value.type
      visitorResult = visitor value
      return false if visitorResult == false

    return false if traverse(value, visitor) == false
  return false if result == false

###*
  @param {Object|Array} object
  @param {Function} callback
  @return {boolean} false if iteration has been stopped
###
iterator = (object, callback) ->
  # Don't use 'for in' both for objects and arrays, not like
  # https://github.com/ariya/esmorph/blob/master/lib/esmorph.js#L76.
  # http://google-styleguide.googlecode.com/svn/trunk/javascriptguide.xml#for-in_loop
  if Array.isArray object
    for item, i in object
      return false if callback(i, item) == false
  else
    for key, value of object
      return false if callback(key, value) == false
  true

###*
  @param {string} source
  @return {Object}
###
parse = (source) ->
  esprima.parse source,
    comment: true
    tokens: true
    range: true
    loc: true

###*
  @param {Object} syntax
  @param {string} source
  @return {Array.<Object>}
###
prepareTokens = (syntax, source) ->
  tokens = syntax.tokens.concat syntax.comments
  sortTokens tokens
  tokens

###*
  @param {Array.<Object>} tokens
  @return {Array}
###
findConstructors = (tokens) ->
  constructors = []
  for token, i in tokens
    nextSibling = tokens[i + 1]
    continue if !isConstructor token, nextSibling
    token.__className = nextSibling.value
    constructors.push token
  constructors

###*
  @param {Object} syntax
  @param {Object} linesToRemove
###
removeInjectedCode = (syntax, linesToRemove) ->
  traverse [syntax], (node) ->
    if isCoffeeInjectedCode node
      for i in [node.loc.start.line..node.loc.end.line]
        linesToRemove[i] = true

###*
  @param {Array.<Object>} constructors
  @param {Array.<Object} tokens
  @param {Object} linesToRemove
###
fixClasses = (constructors, tokens, linesToRemove) ->
  for constructor in constructors
    column = constructor.loc.start.column
    constructorIdx = tokens.indexOf constructor
    start = 0
    end = 0
    namespace = ''
    parentNamespace = ''

    # remove })() and return [ClassName];
    i = constructorIdx
    loop
      token = tokens[++i]
      if token.loc.start.column == column - 2
        line = token.loc.start.line
        linesToRemove[line - 2] = true
        linesToRemove[line - 1] = true
        linesToRemove[line] = true
        end = i - 1
        break

    # find parent if any
    loop
      token = tokens[i++]
      break if !token || token.loc.start.line != line
      if token.type == 'Identifier' ||
        token.type == 'Punctuator' &&
        token.value == '.'
          parentNamespace += token.value

    # remove [ClassName] = (function() {
    i = constructorIdx
    loop
      token = tokens[--i]
      if token.loc.start.column == column - 2
        # read namespace if any
        j = i
        loop
          nextToken = tokens[j++]
          break if nextToken.type == 'Punctuator' && nextToken.value == '='
          namespace += nextToken.value
        namespace = namespace.slice 0, -constructor.__className.length

        linesToRemove[token.loc.start.line] = true
        start = i + 1
        break

    # remove var [ClassName]; for namespace-less classes
    loop
      token = tokens[--i]
      if !token || token.loc.start.column < column - 2
        break
      isNamespaceLessClassDeclaration =
        token.type == 'Keyword' &&
        token.value == 'var' &&
        tokens[i + 1].type == 'Identifier' &&
        tokens[i + 1].value == constructor.__className
      if isNamespaceLessClassDeclaration
        linesToRemove[token.loc.start.line] = true
        break

    # transform function declaration to function expression assigment
    constructor.value = namespace + constructor.__className + ' ='
    tokens[constructorIdx + 1].value = 'function'

    # ensure constructor (with preceding comment if any) to be first in wrapper
    line = tokens[start].loc.start.line
    i = start
    loop
      token = tokens[i++]
      if token.loc.start.line != line
        break
    firstTokenInWrapper = token
    constructorHasComment = tokens[constructorIdx - 1].type == 'Block'
    contructorIsFirst = if constructorHasComment
      tokens[constructorIdx - 1] == firstTokenInWrapper
    else
      firstTokenInWrapper == constructor

    if !contructorIsFirst
      tokensToMove = [constructor]
      i = constructorIdx
      # get constructor tokens
      loop
        token = tokens[++i]
        tokensToMove.push token
        if token.loc.start.column == constructor.loc.start.column
          break

      # handle empty constructor function() {}
      if token.type != 'Punctuator' && token.value != '}'
        tokensToMove.pop()

      # add constructor comment if any
      if constructorHasComment
        tokensToMove.unshift tokens[constructorIdx - 1]

      # move constructor to be first in wrapper
      tokens.splice tokens.indexOf(tokensToMove[0]), tokensToMove.length
      tokens.splice.apply tokens, [tokens.indexOf(firstTokenInWrapper), 0].
        concat tokensToMove

    line = null
    previous = null
    startToken = tokens[start]
    for i in [start..end]
      token = tokens[i]

      # full-qualify [ClassName]'s if needed
      if namespace &&
        token.type == 'Identifier' &&
        token.value == constructor.__className &&
        !(previous.type == 'Punctuator' && previous.value == '.')
          token.value = namespace + token.value

      if parentNamespace &&
        token.type == 'Identifier' &&
        token.value == '_super'
          token.value = parentNamespace

      # fix indentation
      if token.loc.start.line != line
        token.loc.start.column -= 2
        line = token.loc.start.line
      # fix block commment indentation
      if token.type == 'Block'
        token.value = token.value.replace /\n  /g, '\n'

      previous = token
  return

###*
  Is's easy to look for constructors, because the only function declaration
  in CoffeeScript transcompiled output is class constructor.
  http://stackoverflow.com/questions/6548750/function-declaration-in-coffeescript
  @param {Object} token
  @param {Object} nextSibling
  @return {boolean}
###
isConstructor = (token, nextSibling) ->
  token.type == 'Keyword' &&
  token.value == 'function' &&
  nextSibling &&
  nextSibling.type == 'Identifier' &&
  # ctor from __extends injected helper
  nextSibling.value != 'ctor'

###*
  @param {Array.<Object>} tokens
###
sortTokens = (tokens) ->
  tokens.sort (a, b) ->
    if a.range[0] > b.range[0]
      1
    else if a.range[0] < b.range[0]
      -1
    else
      0

###*
  @param {Array.<Object>} tokens
  @param {Object.<string, boolean>} linesToRemove
###
removeLines = (tokens, linesToRemove) ->
  i = tokens.length
  while i--
    token = tokens[i]
    if token.loc.start.line of linesToRemove
      tokens.splice i, 1
  return

###*
  @param {Array.<Object>} tokens
###
aliasRemovedInjectedCode = (tokens) ->
  for token, i in tokens
    continue if token.type != 'Identifier'
    switch token.value
      when '__bind'
        token.type = 'fixed_Identifier'
        # it's ok to change value, we don't need to update loc
        token.value = 'goog.bind'
      when '__indexOf'
        token.type = 'fixed_Identifier'
        token.value = 'goog.array.indexOf'
        # remove .call
        tokens[i + 1].value = ''
        tokens[i + 2].value = ''
        requireGoogArray = true
      when '__slice'
        token.type = 'fixed_Identifier'
        token.value = 'goog.array.slice'
        # remove .call
        tokens[i + 1].value = ''
        tokens[i + 2].value = ''
        requireGoogArray = true
      when '__super__'
        token.type = 'fixed_Identifier'
        token.value = 'superClass_'
      when '__extends'
        token.type = 'fixed_Identifier'
        token.value = 'goog.inherits'
  return

###*
  @param {Array.<Object>} tokens
  @return {string}
###
mergeTokens = (tokens) ->
  source = ''
  for token in tokens
    newLine = false
    if previous
      newLine = token.loc.start.line != previous.loc.end.line
      if newLine
        source += createSpace token.loc.start.column, true
      else
        source += createSpace token.loc.start.column - previous.loc.end.column

    if token.type == 'Block'
      if newLine
        # indent just block comments on new line
        source += "\n/*#{token.value}*/"
      else
        source += "/*#{token.value}*/"
    # CoffeeScript 1.4 does not support inline comments, but 2 will do.
    else if token.type == 'Line'
      source += "//#{token.value}"
    else
      source += token.value
    previous = token
  source

###*
 @param {number} length The number of times to repeat.
 @param {boolean} newLine
 @return {string}
###
createSpace = (length, newLine) ->
  # very rare case, when \ is used in coffee source.
  return '' if length < 0
  space = new Array(length + 1).join ' '
  space = '\n' + space if newLine
  space

###*
  @param {string} source
  @return {string}
###
addGeneratedBy = (source) ->
  '// Generated by github.com/steida/coffee2closure 0.0.14\n' +
  source

###*
  @param {Object} node
  @return {boolean}
###
isCoffeeInjectedCode = (node) ->
  node.type == 'VariableDeclaration' &&
  node.declarations.some (declaration) ->
    declaration.type == 'VariableDeclarator' &&
    declaration.id.name in [
      '__hasProp',
      '__extends',
      '__slice',
      '__bind',
      '__indexOf']