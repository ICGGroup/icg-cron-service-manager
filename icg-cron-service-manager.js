// Generated by CoffeeScript 1.8.0
(function() {
  var CronJob, async, cluster, domain, jobs, logWrapper, moment, path, util, _;

  util = require("util");

  async = require("async");

  path = require("path");

  _ = require("lodash");

  cluster = require('cluster');

  domain = require("domain");

  logWrapper = require("./lib/log-wrapper");

  moment = require('moment');

  CronJob = require('cron').CronJob;

  jobs = [];

  module.exports = function(config, options) {
    var e, handler, job, jobDomain, launchServiceWorkers, restClient, serviceLogin, _ref, _ref1, _ref2, _ref3;
    if (cluster.isMaster) {
      if (!config.jobs || config.jobs.length === 0) {
        throw new Error("Missing required configuration option 'jobs'");
      }
      launchServiceWorkers = function() {
        _.each(cluster.workers, function(w) {
          return w.kill();
        });
        return _.each(config.jobs, function(jobOptions) {
          var e, initJobWorker, jobWorker, lastHeartbeat, _ref, _ref1;
          jobOptions.secToken = config.secToken;
          try {
            if ((_ref = config.log) != null) {
              _ref.debug("forking task job onto worker", jobOptions.job);
            }
            lastHeartbeat = null;
            initJobWorker = function() {
              var worker;
              worker = cluster.fork({
                jobOptions: JSON.stringify(jobOptions)
              });
              lastHeartbeat = new Date();
              worker.on("message", function(msg) {
                return lastHeartbeat = new Date();
              });
              return worker;
            };
            jobWorker = initJobWorker();
            return setInterval(function() {
              var timeSinceHeartbeat, timeout;
              timeSinceHeartbeat = new Date() - lastHeartbeat;
              timeout = moment.duration(config.deadWorkerProcessTimeout || 360000).asMilliseconds();
              if (timeout > 0) {
                if (timeSinceHeartbeat > timeout) {
                  config.log.error("Dead worker detected from job " + jobOptions.job.name + " after timeout of " + timeout + "ms");
                  jobWorker.kill();
                  return jobWorker = initJobWorker();
                }
              } else {
                return config.log.warn("Invalid deadWorkerProcessTimeout (" + config.deadWorkerProcessTimeout + ") in config");
              }
            }, 10000);
          } catch (_error) {
            e = _error;
            if ((_ref1 = config.log) != null) {
              _ref1.error(e);
            }
            throw e;
          }
        });
      };
      if (!config.apiBaseUrl || !config.credentials) {
        if ((_ref = config.log) != null) {
          _ref.warn("API login information not present, launching workers without logging in.  To login to the API, provide an apiBaseUrl and credentials.");
        }
        launchServiceWorkers();
      } else {
        serviceLogin = function(cb) {
          var callOpts, restClient;
          restClient = require("icg-rest-client")(config.apiBaseUrl);
          callOpts = {
            data: {
              userId: config.credentials.user,
              password: config.credentials.password
            }
          };
          return restClient.post(config.sessionPath, callOpts, function(err, response) {
            var _ref1;
            if (err) {
              if ((_ref1 = config.log) != null) {
                _ref1.error(err);
              }
              throw new Error("Unable to log in to the API");
            } else {
              config.secToken = response.body.secToken;
              if (cb) {
                return cb();
              }
            }
          });
        };
        serviceLogin(function() {
          return launchServiceWorkers();
        });
        if (config.refreshLoginInterval) {
          setTimeout(function() {
            return serviceLogin(function() {
              return config != null ? config.log.info("Sec Token Refreshed") : void 0;
            });
          }, config.refreshLoginInterval);
        }
      }
      return cluster.on("disconnect", function(worker) {
        return config.log.warn("A worker process disconnected form the cluster.");
      });
    } else {
      options = JSON.parse(process.env.jobOptions);
      job = options.job;
      config.log = logWrapper(options.job.name, config.log, function(text, meta) {
        process.send({
          heartbeat: true
        });
        return true;
      });
      restClient = require("icg-rest-client")(config.apiBaseUrl, options.secToken);
      if ((_ref1 = config.log) != null) {
        _ref1.info("Loading handler: " + job.script);
      }
      try {
        handler = require(job.script);
      } catch (_error) {
        e = _error;
        if ((_ref2 = config.log) != null) {
          _ref2.error("unable to load:", job.script);
        }
      }
      if ((_ref3 = config.log) != null) {
        _ref3.info("Creating Job Domain for :" + job.script);
      }
      jobDomain = domain.create();
      jobDomain.on("error", function(err) {
        var _ref4;
        if ((_ref4 = config.log) != null) {
          _ref4.error(err.stack);
        }
        setTimeout(function() {
          return process.exit(1);
        }, config.errorRestartDelay || 120000);
        return cluster.worker.disconnect();
      });
      return jobDomain.run(function() {
        var cronJob, running, _ref4;
        if (!config) {
          return (_ref4 = config.log) != null ? _ref4.error("Invalid Config") : void 0;
        }
        running = false;
        cronJob = new CronJob(options.cron, function() {
          var cb, _ref5;
          cb = function(err) {
            var _ref5, _ref6;
            if (err) {
              if ((_ref5 = config.log) != null) {
                _ref5.error(err, job);
              }
            } else {
              if ((_ref6 = config.log) != null) {
                _ref6.info("Job completed", options.job.name);
              }
            }
            return running = false;
          };
          if (!running) {
            if ((_ref5 = config.log) != null) {
              _ref5.info("Job starting", options.job);
            }
            running = true;
            return handler(options, config, cb);
          }
        });
        return cronJob.start();
      });
    }
  };

}).call(this);
