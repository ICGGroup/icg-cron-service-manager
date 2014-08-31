// Generated by CoffeeScript 1.7.1
(function() {
  var CronJob, async, jobs, path, _;

  async = require("async");

  path = require("path");

  _ = require("lodash");

  CronJob = require("cron").CronJob;

  jobs = [];

  module.exports = function(config) {
    var restClient, workerFn;
    restClient = require("icg-rest-client")(config.apiBaseUrl);
    if (!config.jobs || config.jobs.length === 0) {
      throw new Error("Missing required configuration option 'jobs'");
    }

    /*
    
    Required configuraition
    
    config:
      jobs: [
        cron:"* 5 * * * * *"
        job: {
          name:"Do Something"
          script: "./job-assignment"
        }
      ]
     */
    workerFn = function() {
      var callOpts, options, workerCallback;
      if (arguments.length === 1) {
        options = {};
        workerCallback = arguments[0];
      } else {
        options = arguments[0];
        workerCallback = arguments[1];
      }
      if (!config) {
        workerCallback("Invalid Config");
      }
      if (!config.apiBaseUrl) {
        workerCallback("Missing apiBaseUrl");
      }
      if (!config.credentials) {
        workerCallback("Missing credentials");
      }
      if (!config.credentials.user) {
        workerCallback("Missing credentials.user");
      }
      if (!config.credentials.password) {
        workerCallback("Missing credentials.password");
      }
      if (!config.credentials) {
        workerCallback("Missing credentials");
      }
      if (!config.sessionPath) {
        workerCallback("Missing sessionPath");
      }
      callOpts = {
        data: {
          userId: config.credentials.user,
          password: config.credentials.password
        }
      };
      return restClient.post(config.sessionPath, callOpts, function(err, response) {
        var e, handler, _ref;
        if (err) {
          if ((_ref = config.log) != null) {
            _ref.error(err);
          }
          return workerCallback(err);
        } else {
          config.secToken = response.body.secToken;
          config.maxConcurrency || (config.maxConcurrency = 5);
          config.maxLockMinutes || (config.maxLockMinutes = 120);
          try {
            handler = require(path.join(process.cwd(), options.script));
            return handler.apply(this, [options, config, workerCallback]);
          } catch (_error) {
            e = _error;
            return workerCallback(e);
          }
        }
      });
    };
    if (jobs && jobs.length > 0) {
      _.each(jobs, function(job) {
        return job.stop();
      });
      jobs = [];
    }
    return _.each(config.jobs, function(job) {
      var cronJob, e, running, _ref, _ref1;
      running = false;
      try {
        if ((_ref = config.log) != null) {
          _ref.debug("creating job", job.job);
        }
        cronJob = new CronJob(job.cron, function() {
          var cb, _ref1, _ref2;
          cb = function(err) {
            var _ref1, _ref2;
            running = false;
            if (err) {
              return (_ref1 = config.log) != null ? _ref1.error(err, job) : void 0;
            } else {
              return (_ref2 = config.log) != null ? _ref2.info("Job completed", job.job) : void 0;
            }
          };
          if (!running) {
            if ((_ref1 = config.log) != null) {
              _ref1.info("Job starting", job.job);
            }
            running = true;
            return workerFn(job.job, cb);
          } else {
            return (_ref2 = config.log) != null ? _ref2.warn("Job skipped due to already running process.") : void 0;
          }
        });
        jobs.push(cronJob);
        return cronJob.start();
      } catch (_error) {
        e = _error;
        if ((_ref1 = config.log) != null) {
          _ref1.error(e);
        }
        throw e;
      }
    });
  };

}).call(this);
