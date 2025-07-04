// PMD False Positive: Sharing model is not required for Test classes. TODO: Improve SpecifySharingModel rule.
@SuppressWarnings('PMD.SpecifySharingModel')
@isTest
private class AqTest_AqAsync {
    @TestVisible
    private class TestScheduled implements Schedulable {
        // PMD False Positive, required from Interface
        @SuppressWarnings('PMD.EmptyStatementBlock')
        public void execute(SchedulableContext context) {
        }
    }

    @IsTest
    private static void isJobRunning() {
        System.runAs(standardUser()) {
            // Setup
            String jobName = 'TestJob';

            // Exercise
            // Note: Schedule recurring job (cron happens to be for 8 AM and 4 PM M - F)
            System.schedule(jobName, '0 0 8,16 ? 1-5 *', new TestScheduled());

            // Verify
            System.assertEquals(true, AqAsync.isJobRunning(jobName, ''));
        }
    }

    @IsTest
    private static void cleanDeletedSchedule() {
        System.runAs(standardUser()) {
            // Setup
            String jobName = 'TestJob';

            // Exercise
            // Note: Schedule recurring job (cron happens to be for 8 AM and 4 PM M - F)
            System.schedule(jobName, '0 0 8,16 ? 1-5 *', new TestScheduled());
            AqAsync.abortSchedule(jobName);
            AqAsync.cleanDeletedSchedule(jobName);

            // Verify
            System.assertEquals(false, AqAsync.isJobRunning(jobName, ''));
            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM CronTrigger
                    WHERE CronJobDetail.Name = :jobName
                ]
            );
        }
    }

    private static User standardUser() {
        Profile standardUserProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
        ];

        return new User(
            Alias = 'standt',
            Email = 'standarduser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardUserProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'standarduser@testorg.com' + Datetime.now().getTime()
        );
    }
}
