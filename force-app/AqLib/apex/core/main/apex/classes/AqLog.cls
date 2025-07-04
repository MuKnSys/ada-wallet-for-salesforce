/*
 * Copyright (c) 2022, Aquiva Labs LLC. All rights reserved.
 * 
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 * 
 * - Redistributions of source code must retain the above copyright notice, 
 *     this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *     this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * - Neither the name of the Aquiva Labs LLC nor the names of its contributors
 *     may be used to endorse or promote products derived from this software without
 *     specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

/**
 * @description Event logger. [LogDgt__c](https://bitbucket.org/aquiva/aqlib/src/develop/AqLib/core/main/objects/LogDgt__c/) custom object is used.
 * @group apex/core
 */
public inherited sharing class AqLog {

    private static SObjectType LOG_SOBJECT_TYPE = LogDgt__c.getSObjectType();
    private static List<String> LOG_FIELDS = new List<String> {
        'Id', 'LogDate__c', 'Level__c', 'Severity__c', 'Code__c', 'Source__c',
        'ResultType__c', 'ScopeType__c', 'Scope__c', 'Message__c', 'Detail__c'
    };

    public static LogDgt__c generateLogRecord(AqResult result) {
        LogDgt__c log = new LogDgt__c(
            LogDate__c = result.ResultDate == null ? AqEnv.now() : result.ResultDate,
            Level__c = result.Level,
            Severity__c = result.Severity,
            Code__c = result.Code,
            Source__c = result.Source,
            ResultType__c = result.Type,
            ScopeType__c = result.ScopeType,
            Scope__c = result.Scope,
            Message__c = result.Message
        );

        if (result.Detail != null) {
            if (result.Detail instanceof String) {
                log.Detail__c = (String)result.Detail;
            } else {
                log.Detail__c = JSON.serialize(result.Detail);
            }
        } else {
            log.Detail__c = JSON.serialize(result);
        }

        return log;
    }

    /**
     * @description Write the result to a log record
     */
    public static LogDgt__c logResult(AqResult result) {

        LogDgt__c log = generateLogRecord(result);
        // Method creates log records for the application. 
        // Log records should be created in system context, so CRUD/FLS enforcement omitted
        AqDml.insecureInsert(log);
        return log;
    }

    /**
     * @description Convenience, convert exception to result and log
     */
    public static LogDgt__c logException(System.Exception e, String source) {
        return logResult(
            new AqResultBuilder()
                .setException(e)
                .setSource(source)
                .createAqResult()
        );
    }

    /**
     * @description Convenience, convert exception to result and log
     */
    public static LogDgt__c logException(System.Exception e, String source, String scopeType, String scope) {
        return logResult(
            new AqResultBuilder()
                .setException(e)
                .setSource(source)
                .setScopeType(scopeType)
                .setScope(scope)
                .createAqResult()
        );
    }

    /**
     * @description Retrieve a log by ID
     */
    public static LogDgt__c retrieve(Id logId) {
        AqSoql query = new AqSoql(LOG_SOBJECT_TYPE)
            .withColumns(LOG_FIELDS)
            .withWhere('Id = :logId');
        
        return (LogDgt__c) Aq.exactlyOne(
            LogDgt__c.SObjectType, 
            (List<LogDgt__c>) Database.query(query.getQueryString())
        );

    }

    /**
     * @description Return most recent log entry, most useful for testing
     */
    public static LogDgt__c getMostRecent() {

        AqSoql query = new AqSoql(LOG_SOBJECT_TYPE)
            .withColumns(LOG_FIELDS)
            .withOrderBy(new List<String>{'Name DESC'})
            .withRowLimit(1);

        List<LogDgt__c> logs = (List<LogDgt__c>) Database.query(query.getQueryString());

        if (logs.isEmpty()) {
            return null;
        } else {
            return logs[0];
        }
    }

}
