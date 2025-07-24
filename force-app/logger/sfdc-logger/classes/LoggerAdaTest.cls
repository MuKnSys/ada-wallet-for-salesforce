@IsTest
private class LoggerAdaTest {
    private static final String ADMIN_PROFILE_ID = [
        SELECT Id
        FROM Profile
        WHERE Name = 'System Administrator'
        LIMIT 1
    ]
    .Id;
    private static final String STD_USER_PROFILE_ID = [
        SELECT Id
        FROM Profile
        WHERE Name = 'Standard User'
        LIMIT 1
    ]
    .Id;

    @TestSetup
    private static void makeData() {
        String adminUsername = getTestUsername('admin.user{0}@test.com');
        List<User> usersToInsert = new List<User>();
        User adminUser = new User(
            Alias = 'adm',
            Country = 'United Kingdom',
            Email = adminUsername,
            EmailEncodingKey = 'UTF-8',
            LastName = 'admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = ADMIN_PROFILE_ID,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = adminUsername
        );
        usersToInsert.add(adminUser);

        String stdUserUsername = getTestUsername('standard.user{0}@test.com');
        User standardUser = new User(
            Alias = 'suser',
            Country = 'United Kingdom',
            Email = stdUserUsername,
            EmailEncodingKey = 'UTF-8',
            LastName = 'Standard User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = STD_USER_PROFILE_ID,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = stdUserUsername
        );
        usersToInsert.add(standardUser);
        insert usersToInsert;

        System.runAs(adminUser) {
            List<Logger_Config_Ada__c> configs = new List<Logger_Config_Ada__c>();
            Logger_Config_Ada__c defaultConfig = new Logger_Config_Ada__c();
            defaultConfig.SetupOwnerId = UserInfo.getOrganizationId();
            defaultConfig.Is_Logger_Enabled__c = false;
            defaultConfig.Is_Debug_Enabled__c = false;
            defaultConfig.Is_Info_Enabled__c = false;
            defaultConfig.Is_Success_Enabled__c = false;
            defaultConfig.Is_Error_Enabled__c = false;
            configs.add(defaultConfig);

            Logger_Config_Ada__c standardUserConfig = new Logger_Config_Ada__c();
            standardUserConfig.SetupOwnerId = standardUser.Id;
            standardUserConfig.Is_Logger_Enabled__c = true;
            standardUserConfig.Is_Debug_Enabled__c = true;
            standardUserConfig.Is_Info_Enabled__c = true;
            standardUserConfig.Is_Success_Enabled__c = true;
            standardUserConfig.Is_Error_Enabled__c = true;
            configs.add(standardUserConfig);
            insert configs;
        }
    }

    @IsTest
    private static void testLogDisabled() {
        User adminUser = [
            SELECT Id
            FROM User
            WHERE ProfileId = :ADMIN_PROFILE_ID
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Test.startTest();
        System.runAs(adminUser) {
            LoggerAda.logDebug('Test Debug message');
            LoggerAda.logInfo('Test Debug message');
            LoggerAda.logSuccess('Test Debug message');
            LoggerAda.logError('Test Debug message');
            LoggerAda.commitLogs();
        }
        Test.stopTest();

        Integer logsCount = [
            SELECT COUNT()
            FROM Log_Ada__c
            WHERE Running_User__c = :adminUser.Id
        ];

        System.assertEquals(0, logsCount);
    }

    @IsTest
    private static void testLogEnabled() {
        User standardUser = [
            SELECT Id
            FROM User
            WHERE ProfileId = :STD_USER_PROFILE_ID
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Test.startTest();
        System.runAs(standardUser) {
            LoggerAda.logDebug('Test Debug message');
            LoggerAda.logInfo('Test Debug message');
            LoggerAda.logSuccess('Test Debug message');
            LoggerAda.logError('Test Debug message');
            LoggerAda.commitLogs();
        }
        Test.stopTest();

        Integer debugLogsCount = [
            SELECT COUNT()
            FROM Log_Ada__c
            WHERE Running_User__c = :standardUser.Id AND Severity__c = :LoggerAda.LogSeverity.DEBUG.name()
        ];
        Integer infoLogsCount = [
            SELECT COUNT()
            FROM Log_Ada__c
            WHERE Running_User__c = :standardUser.Id AND Severity__c = :LoggerAda.LogSeverity.INFO.name()
        ];
        Integer successLogsCount = [
            SELECT COUNT()
            FROM Log_Ada__c
            WHERE Running_User__c = :standardUser.Id AND Severity__c = :LoggerAda.LogSeverity.SUCCESS.name()
        ];
        Integer errorLogsCount = [
            SELECT COUNT()
            FROM Log_Ada__c
            WHERE Running_User__c = :standardUser.Id AND Severity__c = :LoggerAda.LogSeverity.ERROR.name()
        ];

        System.assertEquals(1, debugLogsCount);
        System.assertEquals(1, infoLogsCount);
        System.assertEquals(1, successLogsCount);
        System.assertEquals(1, errorLogsCount);
    }

    private static String getTestUsername(String usernameTemplate) {
        return String.format(
            usernameTemplate,
            new List<String>{ String.valueOf(System.currentTimeMillis()) + String.valueOf(Math.random() * 100) }
        );
    }
}
