# Simple Salesforce Apex logger

[![CircleCI](https://circleci.com/gh/AndreyFilonenko/sfdc-logger.svg?style=svg)](https://circleci.com/gh/AndreyFilonenko/sfdc-logger) [![codecov](https://codecov.io/gh/AndreyFilonenko/sfdc-logger/branch/main/graph/badge.svg)](https://codecov.io/gh/AndreyFilonenko/sfdc-logger)

<a href="https://githubsfdeploy.herokuapp.com?owner=AndreyFilonenko&repo=sfdc-logger&ref=main">
  <img alt="Deploy to Salesforce"
       src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

## Overview

A minimalistic logger for your Salesforce Apex code.

## Usage

### Logger public API

#### Enums:

-   `Logger.LogSeverity` - an enum containing message severity types: `INFO`, `SUCCESS`, `ERROR` and `DEBUG`.

#### Methods:

-   `static void log(Logger.LogSeverity severity, String message)` - a generic method for logging a message with a specific severity.
-   `static void logInfo(String message)` - a method for logging a message with the predefined `INFO` severity.
-   `static void logSuccess(String message)` - a method for logging a message with the predefined `SUCCESS` severity.
-   `static void logError(String message)` - a method for logging a message with the predefined `ERROR` severity.
-   `static void commitLogs()` - a method for committing logs to database if any.

### Logger methods usage

You can log different kind of messages using `logError`, `logSuccess` or `logInfo` methods, also it is possible to construct your own log message using a generic `log` method:

```java
Logger.logError('Test Error message');
Logger.logSuccess('Test Success message');
Logger.logInfo('Test Info message');

Logger.log(Logger.LogSeverity.DEBUG, 'Test Debug message');
```

Dont forget to call `commitLogs` method in the end of your execution context or another suitable place:

```java
Logger.commitLogs();
```

The typical usage of logger is in `try...catch...finally` blocks:

```java
try {
    // Some glitchy code
    throw new NullPointerException('error message');
} catch (Exception ex) {
    Logger.logError(ex.getMessage());
} finally {
    Logger.commitLogs();
}
```

### Configuration and feature enablement

-   For the convenience of usage and determining the logging events was included a hierarchy custom setting support:
    1. Go the the Setup -> Custom Settings -> Logger Config
    2. Define a default logging behavior using org-wide custom setting values.
    3. In case of a specific user or profile should be logged create a custom setting record for them and define a logging level using the checkboxes.
-   You can integrate the logger switch in any other suitable way.

## License

The MIT License (MIT). Please see [License File](LICENSE) for more information.
