public without sharing class LoggerService {
    private Logger_Config__c loggerSettings;

    public LoggerService() {
        loggerSettings = Logger_Config__c.getOrgDefaults();
    }

    public Logger_Config__c getConfig() {
        return loggerSettings;
    }

    public void updateLoggerService(Boolean enabled) {
        loggerSettings.Is_Debug_Enabled__c = enabled;
        loggerSettings.Is_Error_Enabled__c = enabled;
        loggerSettings.Is_Info_Enabled__c = enabled;
        loggerSettings.Is_Logger_Enabled__c = enabled;
        loggerSettings.Is_Success_Enabled__c = enabled;

        upsert as system loggerSettings;
    }

    public Boolean isLoggingEnabled() {
        return loggerSettings.Is_Logger_Enabled__c;
    }
}
