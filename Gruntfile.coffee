module.exports = (grunt) ->

  path = require 'path'

  # to preserve directory structure
  coffeeLib2SrcDest = grunt.file.expandMapping '**/*.coffee', 'lib/',
    cwd: 'src/'
    ext: '.js'
    rename: (dest, matchedSrcPath) -> path.join dest, matchedSrcPath

  grunt.initConfig

    coffee:
      options:
        bare: true
      all:
        files: coffeeLib2SrcDest.concat [
          expand: true
          src: 'test_app/**/*.coffee'
          ext: '.js'
        ,
          expand: true
          src: 'test/**/*.coffee'
          ext: '.js'
        ]

    simplemocha:
      all:
        src: [
          'node_modules/should/lib/should.js'
          'test/**/*.js'
        ]

    watch:
      coffee:
        files: [
          'src/**/*.coffee'
          'test/**/*.coffee'
          'test_app/**/*.coffee'
        ]
        tasks: 'coffee'

      simplemocha:
        files: [
          'lib/**/*.js'
          'test/**/*.js'
        ]
        tasks: 'simplemocha'

    esteDeps:
      options:
        depsWriterPath: 'bower_components/closure-library/closure/bin/build/depswriter.py'
      testApp:
        options:
          output_file: 'test_app/assets/deps.js'
          prefix: '../../../../'
          root: [
            'bower_components/closure-library'
            'test_app/js'
          ]

    esteBuilder:
      options:
        closureBuilderPath: 'bower_components/closure-library/closure/bin/build/closurebuilder.py'
        compilerPath: 'bower_components/closure-compiler/compiler.jar'
        namespace: 'app.start'
        compilerFlags: [
          '--output_wrapper="(function(){%output%})();"'
          '--compilation_level="ADVANCED_OPTIMIZATIONS"'
          '--warning_level="VERBOSE"'
        ]
      testApp:
        options:
          root: [
            'bower_components/closure-library'
            'test_app/js'
          ]
          outputFilePath: 'test_app/assets/app.js'
          depsPath: 'test_app/assets/deps.js'

    release:
      options:
        bump: true
        add: true
        commit: true
        tag: true
        push: true
        pushTags: true
        npm: true

  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-este'
  grunt.loadNpmTasks 'grunt-release'
  grunt.loadNpmTasks 'grunt-simple-mocha'

  grunt.registerTask 'install', [
    'coffee'
  ]

  grunt.registerTask 'test', [
    'install', 'simplemocha'
  ]

  grunt.registerTask 'run', [
    'test', 'watch'
  ]

  grunt.registerTask 'coffee2closure', ->
    coffee2closure = require './lib/coffee2closure'
    for path in grunt.file.expand 'test_app/js/*.js'
      src = grunt.file.read path
      src = coffee2closure.fix src
      grunt.file.write path, src
      grunt.log.writeln "File #{path} fixed."

  grunt.registerTask 'buildTestApp', [
    'coffee', 'coffee2closure', 'esteDeps:testApp', 'esteBuilder:testApp'
  ]

  grunt.registerTask 'default', 'run'