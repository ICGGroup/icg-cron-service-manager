## ICG Cron Service Manager

### Required Configuration

The following configuration elements are required:

    config: {
      apiBaseUrl: "http://localhost:3000",
      sessionPath: "ap/sessions",
      credentials: {
        user: "USER"
        password: "SECRET"
      }
      job: [...]
    }


### Job Configuration


    config: {
      jobs: [
        cron:"* 5 * * * * *",
        job: {
          name:"Do Something",
          script: "./job-assignment"
        }
      ]
    }


### Workers

Workers are exported functions that accept 3 parameters, job options, a config object and a callback.  Note:  Workers must call the callback or subsequent runs will be aborted.  This is to prevent two jobs from overlapping.
