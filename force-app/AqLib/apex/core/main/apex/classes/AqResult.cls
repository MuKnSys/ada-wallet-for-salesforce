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
 * @description The result of an operation.
 * Can represent any exception or set of exceptions, as well as success, failures, or warning results.
 * Intended to be fully serializable and structured to allow programmatic analysis.
 * 
 * @group apex/core
 */
public inherited sharing class AqResult implements Aq.Formatable {

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Constants

    // @start-group Standard result types
    public static final String RESULT_TYPE_VALIDATION = 'Validation';
    public static final String RESULT_TYPE_SHIELDED = 'Shielded';
    public static final String RESULT_TYPE_DML_ROW_DETAIL = 'DmlRowDetail';
    public static final String RESULT_TYPE_SAVE = 'SaveResult';
    public static final String RESULT_TYPE_DELETE = 'DeleteResult';
    public static final String RESULT_TYPE_UPSERT = 'UpsertResult';
    public static final String RESULT_TYPE_EMAIL = 'EmailResult';
    public static final String RESULT_TYPE_EMAIL_ERROR = 'SendEmailError';
    public static final String RESULT_TYPE_DATABASE_ERROR = 'DatabaseError';
    // @end-group

    // @start-group Valid severities
    /**
     * @description Success
     */
    public static final String SEVERITY_SUCCESS = 'Success';
    /**
     * @description Success with information
     */
    public static final String SEVERITY_INFORMATION = 'Information';		
    /**
     * @description Success with warning
     */
    public static final String SEVERITY_WARNING = 'Warning';				
    /**
     * @description Some records succeeded and some failed
     */
    public static final String SEVERITY_PARTIAL_ERROR = 'PartialError';		
    /**
     * @description Never tried due to other errors
     */
    public static final String SEVERITY_ABORTED = 'Aborted';				
    /**
     * @description Would have succeeded but rolled back due to other errors
     */
    public static final String SEVERITY_ROLLED_BACK = 'RolledBack';			
    /**
     * @description Failure
     */
    public static final String SEVERITY_ERROR = 'Error';					

    public static final Set<String> SEVERITIES_ALL = new Set<String>{
        SEVERITY_SUCCESS, SEVERITY_INFORMATION, SEVERITY_WARNING,
        SEVERITY_PARTIAL_ERROR, SEVERITY_ABORTED, SEVERITY_ROLLED_BACK, SEVERITY_ERROR
    };
    public static final Set<String> SEVERITIES_ERROR = new Set<String> {
        SEVERITY_ABORTED, SEVERITY_ERROR
    };
    public static final Map<String, Integer> SEVERITIES_ORDER = new Map<String, Integer>{
        SEVERITY_SUCCESS => 0, SEVERITY_INFORMATION => 1, SEVERITY_WARNING => 2, SEVERITY_PARTIAL_ERROR => 3,
        SEVERITY_ABORTED => 4, SEVERITY_ROLLED_BACK => 5, SEVERITY_ERROR => 6
    };
    // @end-group

    // @start-group Valid levels
    /**
     * @description Result relates directly to user actions -- end user can see details
     */
    public static final String LEVEL_USER = 'User';				
    /**
     * @description Result relates to business rules -- end user can see details
     */
    public static final String LEVEL_BUSINESS = 'Business';		
    /**
     * @description Internal -- details should be shielded from end user
     */
    public static final String LEVEL_INTERNAL = 'Internal';

    public static Set<String> LEVELS_ALL = new Set<String>{
        LEVEL_USER, LEVEL_BUSINESS, LEVEL_INTERNAL
    };
    public static Set<String> LEVELS_SHIELD = new Set<String>{
        LEVEL_INTERNAL
    };
    // @end-group

    // @start-group Standard scope types
    /**
     * @description Object record
     */
    public static final String SCOPE_TYPE_RECORD = 'Record';		
    /**
     * @description Object field
     */
    public static final String SCOPE_TYPE_FIELD = 'Field';			
    public static final String SCOPE_TYPE_EMAIL = 'Email';
    // @end-group

    // @start-group Standard codes
    public static final String CODE_CREATED = 'Created';
    public static final String CODE_UPDATED = 'Updated';
    public static final String CODE_DELETED = 'Deleted';
    // @end-group

    /**
     * @description Database status codes that can be considered business level not internal
     */
    public static Set<StatusCode> BUSINESS_STATUS_CODES = new Set<StatusCode> {
        StatusCode.DUPLICATES_DETECTED, StatusCode.DUPLICATE_VALUE, StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION
    };

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Result Properties

    /**
     * @description Type of result, usually an exception type
     */
    public String Type {get;set;}
    /**
     * @description Identifies severity of the result
     */
    @AuraEnabled
    public String Severity {get;set;}
    /**
     * @description Identifies the audience that should be able to see the error details
     */
    public String Level {get;set;}
    /**
     * @description Identifies the data being reported on. Could be object, field, record, etc.
     * E.g. 'Field'
     */
    public String ScopeType {get;set;}	
    /**
     * @description E.g. 'DocumentName__c'
     */
    public String Scope {get;set;}		
    /**
     * @description Identifies the source component/method.
     */
    public String Source {get;set;}
    /**
     * @description Invariant identifier for the result (vs. Message which is localized and may change)
     */
    @AuraEnabled
    public String Code {get;set;}
    /**
     * @description General message
     */
    @AuraEnabled
    public String Message {get;set;}
    /**
     * @description Date/time of result
     */
    public DateTime ResultDate {get;set;}
    /**
     * @description Object with additional detail, must be serializable
     */
    public Object Detail {get;set;}
    /**
     * @description For use with Lightning server actions or any other case where the result needs to return a value of the operation
     * When used, the Type field should indicate the type of the value
     */
    @AuraEnabled
    public Object ReturnValue {get;set;}
    /**
     * @description Sub-results if relevant
     */
    @AuraEnabled
    public List<AqResult> SubResults {get;set;}

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Constructors

    /**
     * Use <<AqResultBuilder>> to simplify AqResult creation
     * @Usage
     * Use <<AqResult>> as a response wrapper for your custom baseService.LightningElement LWC component.
     * See lwc-core\main\lwc\networkService.js.
     *
     * Apex controller:
     *
     * @example
     * &#64;AuraEnabled
     * public static AqResult getTaskMetadata() {
     *     try {
     *         return new AqResultBuilder()
     *             .setSeverity(AqResult.SEVERITY_SUCCESS)
     *             .setReturnValue(new TaskMetadataModel())
     *             .createAqResult();
     *     } catch (Exception e) {
     *         return AqResultBuilder.getBadResult(e.getMessage());
     *     }
     * }
     *
     * // LWC component (extending baseService.LightningElement):
     * // import getTaskMetadata from '&#64;salesforce/apex/YourController.getTaskMetadata';
     *
     * // connectedCallback() {
     * //     this.sfData.get(getTaskMetadata)
     * //         .then(response => {
     * //             this.taskMeta = response;
     * //         })
     * //         .catch(error => {
     * //             this.showToast(error);
     * //         });
     * // }
     */
    public AqResult(
        String type, String severity, String level, String scopeType, String source, String scope, String code,
        String message, Object detail, Object returnValue, Datetime resultDate, List<AqResult> subResults
    ) {
        this.Type = type;
        this.Severity = severity;
        this.Level = level;
        this.ScopeType = scopeType;
        this.Source = source;
        this.Scope = scope;
        this.Code = code;
        this.Message = message;
        this.Detail = detail;
        this.ReturnValue = returnValue;
        this.ResultDate = resultDate;
        this.SubResults = subResults;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Instance Methods

    /**
     * @description Return true if has an error severity
     * Does NOT include partial error
     */
    public Boolean hasError() {
        return SEVERITIES_ERROR.contains(this.Severity);
    }

    /**
     * @description Returns true if severity is at or worse than specified severity
     */
    public Boolean severityAtLeast(String severity) {
        return SEVERITIES_ORDER.get(this.Severity) >= SEVERITIES_ORDER.get(severity);
    }

    /**
     * @description Dump as text
     */
    public override String toString() {

        return JSON.serializePretty(this);

    }

    /**
     * @description Convenience for adding subresult only if not null
     */
    public AqResult addSubResult(AqResult subResult) {

        if (this.SubResults == null) {
            this.SubResults = new List<AqResult> { subResult };
        } else if (subResult != null) {
            this.SubResults.add(subResult);
        }

        return subResult;

    }

    /**
     * @description Convenience for adding subresult only if not null
     */
    public AqResult addSubResultAndRollup(AqResult subResult) {

        if (this.SubResults == null) {
            this.SubResults = new List<AqResult> { subResult };
        } else if (subResult != null) {
            this.SubResults.add(subResult);
            this.rollupSeverity();
        }

        return subResult;

    }

    /**
     * @description Go through all subresults and apply worst severity to this result.
     * This method is never called recursively, only looks at immediate child subresults.
     */
    public void rollupSeverity() {
        rollupSeverity(false, SEVERITY_ABORTED);
    }

    /**
     * @description Go through all subresults and apply worst severity to this result.
     * This method is never called recursively, only looks at immediate child subresults.
     */
    public String rollupSeverity(Boolean allOrNone, String successSeverity) {

        String currentSeverity = SEVERITY_SUCCESS;
        Boolean someSuccess = false;
        if (this.SubResults != null) {
            for (AqResult subResult : this.SubResults) {
                if (subResult.Severity == SEVERITY_SUCCESS) {
                    someSuccess = true;
                } else if (SEVERITIES_ORDER.get(subResult.Severity) > SEVERITIES_ORDER.get(currentSeverity)) {
                    currentSeverity = subResult.Severity;
                }
            }
        }

        if (currentSeverity == SEVERITY_ERROR && someSuccess) {
            if (allOrNone == true) {
                //Change successes to RolledBack or Aborted
                for (AqResult subResult : this.SubResults) {
                    if (subResult.Severity == SEVERITY_SUCCESS) {
                        subResult.Severity = successSeverity;
                    }
                }
                this.Severity = SEVERITY_ERROR;
            } else {
                this.Severity = SEVERITY_PARTIAL_ERROR;
            }
        } else {
            this.Severity = currentSeverity;
        }

        return this.Severity;

    }

    /**
     * @description Merge the specified result into the current one.
     * Use when you need to apply the result of an operation to some existing ongoing result.
     * Essentially merges sub-results together and discards the result being merged in.
     */
    public AqResult mergeResult(AqResult result) {

        if (result != null && result.SubResults != null) {
            for (AqResult subResult : result.SubResults) {

                //Merge scope
                if (String.isEmpty(subResult.Scope)) {
                    subResult.Scope = result.Scope;
                } else if (!String.isEmpty(result.Scope)) {
                    subResult.Scope = result.Scope + '.' + subResult.Scope;
                }

                if (this.SubResults == null) {
                    this.SubResults = new List<AqResult>();
                }

                this.SubResults.add(subResult);

            }
        }

        rollupSeverity();

        return result;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Static Methods

    /**
     * @description Returns whether any result in the list has an error. Results are allowed to be null.
     */
    public static Boolean hasError(AqResult[] results) {

        for (AqResult result : results) {
            if (result != null && result.hasError()) {
                return true;
            }
        }

        return false;
    }

    /**
     * @description Decide whether the result details should be shown to the user, and if not, log and make generic result.
     */
    public static AqResult shield(AqResult result) {

        if (AqEnv.isDebugMode != true && LEVELS_SHIELD.contains(result.Level)) {

            //This exception must be shielded from the user and replaced with generic
            LogDgt__c logRecord = AqLog.logResult(result);

            //Create generic message result, with reference to log ID
            AqResult shieldResult = new AqResultBuilder()
                .setType(RESULT_TYPE_SHIELDED)
                .setSeverity(result.Severity)
                .setLevel(result.Level)
                .setMessage(AqString.format(Label.Aq_M_InternalError, logRecord.Id))
                .createAqResult();
            return shieldResult;

        }

        return result;
    }

    /**
     * @description Shield directly from exception
     */
    public static AqResult shield(System.Exception e) {
        return shield(new AqResultBuilder().setException(e).createAqResult());
    }

}
