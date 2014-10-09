_ = require('lodash')

module.exports = (name, logger, interceptFn)->
  logWrapper = (func, text, meta=null)->
    if _.isString(text)
      text = "[#{name}] #{text}"
    if interceptFn
      doLog = interceptFn.apply(this, [text, meta])
    else
      doLog = true
    if doLog
      func.apply(this, [text, meta])

  wrapped =
    debug:_.wrap logger.debug, logWrapper
    verbose:_.wrap logger.verbose, logWrapper
    info:_.wrap logger.info, logWrapper
    warn:_.wrap logger.warn, logWrapper
    error:_.wrap logger.error, logWrapper
