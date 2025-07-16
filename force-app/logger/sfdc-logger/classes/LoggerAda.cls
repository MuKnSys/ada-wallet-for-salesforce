public with sharing class LoggerAda {
    private static final Logger_Config_Ada__c LOGGER_CONFIG = Logger_Config_Ada__c.getInstance();
    private static List<Log_Ada__c> logs = new List<Log_Ada__c>();

    public static void log(LoggerAda.LogSeverity severity, String message) {
        if (severity != null && isEnabled(severity)) {
            Log_Ada__c log = new Log_Ada__c();
            log.Severity__c = severity.name();
            log.Message__c = message;
            log.Running_User__c = UserInfo.getUserId();
            log.Logged_at__c = DateTime.now();
            logs.add(log);
        }
    }

    public static void logDebug(String message) {
        log(LoggerAda.LogSeverity.DEBUG, message);
    }

    public static void logInfo(String message) {
        log(LoggerAda.LogSeverity.INFO, message);
    }

    public static void logSuccess(String message) {
        log(LoggerAda.LogSeverity.SUCCESS, message);
    }

    public static void logError(String message) {
        log(LoggerAda.LogSeverity.ERROR, message);
    }

    public static void logError(Exception e) {
        log(LoggerAda.LogSeverity.ERROR, e.getTypeName() + ': ' + e.getMessage() + '\n\n' + e.getStackTraceString());
    }

    public static void commitLogs() {
        if (!logs.isEmpty()) {
            // System mode as logs should be inserted nevertheless of permissions that user has
            insert as system logs;
            logs.clear();
        }
    }

    private static Boolean isEnabled(LoggerAda.LogSeverity severity) {
        Boolean isEnabled = false;
        if (LOGGER_CONFIG.Is_Logger_Enabled__c) {
            switch on severity {
                when DEBUG {
                    isEnabled = LOGGER_CONFIG.Is_Debug_Enabled__c;
                }
                when INFO {
                    isEnabled = LOGGER_CONFIG.Is_Info_Enabled__c;
                }
                when SUCCESS {
                    isEnabled = LOGGER_CONFIG.Is_Success_Enabled__c;
                }
                when ERROR {
                    isEnabled = LOGGER_CONFIG.Is_Error_Enabled__c;
                }
            }
        }

        return isEnabled;
    }

    public enum LogSeverity {
        DEBUG,
        INFO,
        SUCCESS,
        ERROR
    }
}
