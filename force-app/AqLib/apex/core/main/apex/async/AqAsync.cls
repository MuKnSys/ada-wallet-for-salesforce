/**
 * @group apex/core
 */
public inherited sharing class AqAsync {
    public static final Set<String> STATUSES_DELETED_SCHEDULED_JOB = new Set<String>{ 'DELETED' };

    private static final Set<String> STATUSES_PROGRESS_ASYNC_JOB = new Set<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    private static final Set<String> STATUSES_PROGRESS_SCHEDULED_JOB = new Set<String>{
        'WAITING',
        'ACQUIRED',
        'EXECUTING',
        'PAUSED',
        'BLOCKED',
        'PAUSED_BLOCKED'
    };

    private static final String SCHEDULED_JOB_ID = 'scheduledJobId';
    private static final String SCHEDULED_JOB_NAME = 'scheduledJobName';

    public static Boolean isJobRunning(String jobName, String className) {
        return isScheduledJobRunning(jobName) || isAsyncApexJobRunningByApexClassName(className);
    }

    public static Boolean isScheduledJobRunning(String jobName) {
        if (String.isBlank(jobName)) {
            return false;
        }

        jobName += '%';
        return [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE :jobName AND State IN :STATUSES_PROGRESS_SCHEDULED_JOB
                WITH SECURITY_ENFORCED
                LIMIT 1
            ] > 0;
    }

    public static Boolean isAsyncApexJobRunningByApexClassName(String className) {
        if (String.isBlank(className)) {
            return false;
        }

        className = className.contains(AqString.DOT) ? className.substringAfter(AqString.DOT) : className;

        return [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = :className AND Status IN :STATUSES_PROGRESS_ASYNC_JOB
                WITH SECURITY_ENFORCED
                LIMIT 1
            ] > 0;
    }

    public static void abortSchedule(String jobName) {
        Aq.requireValue(SCHEDULED_JOB_NAME, jobName);

        try {
            for (CronTrigger job : [
                SELECT Id
                FROM CronTrigger
                WHERE CronJobDetail.Name = :jobName AND State IN :STATUSES_PROGRESS_SCHEDULED_JOB
                WITH SECURITY_ENFORCED
                LIMIT 1
            ]) {
                System.abortJob(job.Id);
            }
        } catch (Exception ex) {
            AqLog.logException(ex, jobName);
        }
    }

    public static void abortSchedule(Id jobId) {
        Aq.requireValue(SCHEDULED_JOB_ID, jobId);

        try {
            System.abortJob(jobId);
        } catch (Exception ex) {
            AqLog.logException(ex, jobId);
        }
    }

    // Note: Sometimes we can't setup new scheduled job, because there is exists old one with status = DELETED
    public static void cleanDeletedSchedule(String jobName) {
        Aq.requireValue(SCHEDULED_JOB_NAME, jobName);
        try {
            for (CronTrigger job : [
                SELECT Id
                FROM CronTrigger
                WHERE CronJobDetail.Name = :jobName AND State IN :STATUSES_DELETED_SCHEDULED_JOB
                WITH SECURITY_ENFORCED
                LIMIT 10
            ]) {
                System.abortJob(job.Id);
            }
        } catch (Exception ex) {
            AqLog.logException(ex, jobName);
        }
    }
}
