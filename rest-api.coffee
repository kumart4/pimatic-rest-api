module.exports = (env) ->
  fs = require 'fs'

  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'
  __ = env.require('i18n').__
  semver = env.require 'semver'

  class RestApi extends env.plugins.Plugin
    config: null

    init: (app, framework, @config) =>
      
      sendSuccessResponse = (res, data = {}) =>
        data.success = true
        res.send 200, data

      sendErrorResponse = (res, error, statusCode = 400) =>
        message = null
        if error instanceof Error
          message = error.message
          env.logger.error error.message
          env.logger.debug error.stack
        else
          message = error
        res.send statusCode, {success: false, error: message}

      app.get "/api/device/:actuatorId/:actionName", (req, res, next) =>
        actuator = framework.getDeviceById req.params.actuatorId
        if actuator?
          #TODO: add parms support
          if actuator.hasAction req.params.actionName
            result = actuator[req.params.actionName]() 
            Q.when(result,  =>
              sendSuccessResponse res
            ).catch( (error) =>
              sendErrorResponse res, error, 500
            ).done()
          else
            sendErrorResponse res, 'device hasn\'t that action'
        else sendErrorResponse res, 'device not found'


      app.post "/api/rule/:ruleId/update", (req, res, next) =>
        ruleId = req.params.ruleId
        ruleString = req.body.rule
        active = (req.body.active is "true")
        unless ruleId? then return sendErrorResponse res, 'No ruleId given', 400
        unless ruleString? then return sendErrorResponse res, 'No rule given', 400
        framework.ruleManager.updateRuleByString(ruleId, ruleString, active).then( =>
          sendSuccessResponse res
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()


      app.post "/api/rule//add", (req, res, next) =>
        sendErrorResponse res, 'No id given', 400
        
      app.post "/api/rule/:ruleId/add", (req, res, next) =>
        ruleId = req.params.ruleId
        ruleString = req.body.rule
        active = (req.body.active is "true")
        unless ruleId? then return sendErrorResponse res, 'No ruleId given', 400
        unless ruleString? then return sendErrorResponse res, 'No rule given', 400
        framework.ruleManager.addRuleByString(ruleId, ruleString, active).then( =>
          sendSuccessResponse res
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()

      app.get "/api/rule/:ruleId/remove", (req, res, next) =>
        ruleId = req.params.ruleId
        try
          framework.ruleManager.removeRule ruleId
          sendSuccessResponse res
        catch error
          sendErrorResponse res, error, 500

      app.get "/api/messages", (req, res, next) =>
        memoryTransport = env.logger.transports.memory
        sendSuccessResponse res, { messages: memoryTransport.getBuffer() }

      app.get "/api/devices", (req, res, next) =>
        devicesList = for id, a of framework.devices 
          id: a.id, name: a.name
        sendSuccessResponse res, { devices: devicesList }

      app.get "/api/plugins/installed", (req, res, next) =>
        framework.pluginManager.getInstalledPlugins().then( (plugins) =>

          pluginList = 
            for name in plugins
              packageJson = framework.pluginManager.getInstalledPackageInfo name
              name = name.replace 'pimatic-', ''
              loadedPlugin = framework.getPlugin name
              listEntry = 
                name: name
                active: loadedPlugin?
                description: packageJson.description
                version: packageJson.version
                homepage: packageJson.homepage

          sendSuccessResponse res, { plugins: pluginList}
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()


      app.get "/api/plugins/search", (req, res, next) =>
        framework.pluginManager.searchForPlugins().then( (plugins) =>
          pluginList =
            for k, p of plugins 
              name = p.name.replace 'pimatic-', ''
              loadedPlugin = framework.getPlugin name
              installed = framework.pluginManager.isInstalled p.name
              packageJson = (
                if installed then framework.pluginManager.getInstalledPackageInfo p.name
                else null
              )
              listEntry =
                name: name
                description: p.description
                version: p.version
                installed: installed
                active: loadedPlugin?
                isNewer: (if installed then semver.gt(p.version, packageJson.version) else false)


          sendSuccessResponse res, { plugins: pluginList}
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()
        
      app.post "/api/plugins/add", (req, res, next) =>
        plugins = req.body.plugins
        unless plugins? then return sendErrorResponse res, "No plugins given", 400
        pluginNames = (p.plugin for p in framework.config.plugins)
        added = []
        for p in plugins
          unless p in pluginNames
            framework.config.plugins.push
              plugin: p
            added.push p
        framework.saveConfig()
        sendSuccessResponse res, added: added

      app.post "/api/plugins/remove", (req, res, next) =>
        plugins = req.body.plugins
        unless plugins? then return sendErrorResponse res, "No plugins given", 400
        removed = []
        for p, i in framework.config.plugins
          if p.plugin in plugins
            framework.config.plugins.splice(i, 1)
            removed.push p.plugin
        framework.saveConfig()
        sendSuccessResponse res, removed: removed

      app.get "/api/outdated/pimatic", (req, res, next) =>
        framework.pluginManager.isPimaticOutdated().then( (result) =>
          sendSuccessResponse res, isOutdated: result 
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()

      app.get "/api/outdated/plugins", (req, res, next) =>
        framework.pluginManager.getOutdatedPlugins().then( (result, t2) =>
          sendSuccessResponse res, outdated: result 
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()

      app.post "/api/update", (req, res, next) =>
        modules = req.body.modules
        framework.pluginManager.update(modules).then( (result) =>
          sendSuccessResponse res, result: result
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()
       
      app.get "/api/restart", (req, res, next) =>
        try
          framework.restart()
          sendSuccessResponse res
        catch error
          sendErrorResponse res, error, 406

  return new RestApi