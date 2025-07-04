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
 * @description The Builder for <<AqResult>> object.
 * Use [createAqResult](#public-aqresult-createaqresult) method to assemble <<AqResult>> instance.
 * 
 * @group apex/core
 */
public inherited sharing class AqResultBuilder {

    private String type;
    private String severity;
    private String level;
    private String scopeType;
    private String source;
    private String scope;
    private String code;
    private String message;
    private Object detail;
    private Object returnValue;
    private Datetime resultDate;
    private List<AqResult> subResults;

    @TestVisible
    private static final String EMAIL_ERROR_MESSAGE = 'Email errors';
    @TestVisible
    private static final String SAVE_ERROR_MESSAGE = 'Save errors';
    @TestVisible
    private static final String UPSERT_ERROR_MESSAGE = 'Upsert errors';
    @TestVisible
    private static final String DELETE_ERROR_MESSAGE = 'Delete errors';

    /**
     * @description Use `createAqResult` as a final method to create AqResult
     * @return assembled AqResult record
     * 
     * @example
     * // wrap an Exception in AqResult
     * AqResult result = new AqResultBuilder()
     *      .setException(myException)
     *      .createAqResult();
     * 
     * 
     * // set inserted records as a AqResult.ReturnValue 
     * // and wrap Database.SaveResult in AqResult.SubResults
     * // See AqDML.cls
     * List<AqResult> dmlResults = AqDML.secureInsertWrapped(sObjectsToInsert, true);
     * AqResult result = new AqResultBuilder()
     *      .setReturnValue(sObjectsToInsert)
     *      .addSubResults(dmlResults)
     *      .createAqResult();
     * 
     * 
     * // assemble AqResult with Type, Level, Scope and ScopeType
     * AqResult result = new AqResultBuilder()
     *      .setType('UpsertResourceResult')
     *      .setLevel(AqResult.LEVEL_BUSINESS)
     *      .setScopeType(SCOPE_TYPE_RESOURCE)
     *      .setScope('ResourceName')
     *      .createAqResult()
     */
    public AqResult createAqResult() {
        return new AqResult(
            type, severity, level, scopeType, source, scope, code, message,
            detail, returnValue, resultDate, subResults
        );
    }

    public AqResultBuilder setException(System.Exception e) {

        if (e instanceof AqException) {

            //An AqException is based on a result, so copy all values from that result
            //This allows a result to be thrown as an exception and then later recovered as a result.
            AqException ae = ((AqException) e);
            this.severity = Aq.ifNull(ae.Result.Severity, AqResult.SEVERITY_ERROR);
            this.level = Aq.ifNull(ae.Result.Level, AqResult.LEVEL_INTERNAL);
            this.type = Aq.ifNull(ae.Result.Type, e.getTypeName());
            this.source = ae.Result.Source;
            this.scopeType = ae.Result.ScopeType;
            this.scope = ae.Result.Scope;
            this.code = ae.Result.Code;
            this.message = ae.getMessage();
            this.detail = ae.getDetail();
            this.returnValue = ae.Result.ReturnValue;
            this.resultDate = AqEnv.now();

            if (ae.Result.SubResults != null) {
                this.subResults = ae.Result.SubResults.clone();
            }

            if (e instanceof Aq.UserException) {
                this.level = AqResult.LEVEL_USER;
            } else if (e instanceof Aq.BusinessException) {
                this.level = AqResult.LEVEL_BUSINESS;
            }
        } else {

            this.severity = AqResult.SEVERITY_ERROR;
            this.type = e.getTypeName();
            this.message = e.getMessage();
            this.detail = AqException.getExceptionDetail(e);
            this.level = AqResult.LEVEL_INTERNAL;
            this.resultDate = AqEnv.now();

            if (e.getCause() != null) {
                this.addSubResult(new AqResultBuilder().setException(e.getCause()).createAqResult());
            } else if (e instanceof System.DmlException || e instanceof System.EmailException) {

                //Make each DML record result detail a sub-result
                Integer dmlNum = e instanceof System.DmlException
                    ? ((System.DmlException) e).getNumDml()
                    : ((System.EmailException) e).getNumDml();

                for (Integer i = 0; i < dmlNum; i++) {

                    AqException.DmlRowDetail rowDetail;
                    if (e instanceof System.DmlException) {
                        rowDetail = new AqException.DmlRowDetail((System.DmlException) e, i);
                    } else {
                        rowDetail = new AqException.DmlRowDetail((System.EmailException) e, i);
                    }

                    this.addSubResult(
                        new AqResultBuilder()
                            .setSeverity(AqResult.SEVERITY_ERROR)
                            .setType(AqResult.RESULT_TYPE_DML_ROW_DETAIL)
                            .setDetail(rowDetail)
                            .createAqResult()
                    );
                }
            }
        }

        return this;
    }

    public AqResultBuilder setSaveResult(Database.SaveResult saveResult, SObjectType sObjectType) {
        return setSaveResult(saveResult, sObjectType, null);
    }

    public AqResultBuilder setSaveResult(Database.SaveResult saveResult, SObjectType sObjectType, String scope) {

        this.type = AqResult.RESULT_TYPE_SAVE;
        this.level = AqResult.LEVEL_BUSINESS;
        this.returnValue = saveResult.getId();
        this.scopeType = AqResult.SCOPE_TYPE_RECORD;

        if (String.isNotBlank(scope)) {
            this.scope = scope;
            if (saveResult.getId() != null) {
                this.scope += ': ' + saveResult.getId();
            }
        } else {
            this.scope = saveResult.getId();
        }

        if (saveResult.isSuccess()) {
            this.severity = AqResult.SEVERITY_SUCCESS;
        } else {
            this.severity = AqResult.SEVERITY_ERROR;
            this.message = SAVE_ERROR_MESSAGE;
            for (Database.Error databaseError : saveResult.getErrors()) {
                this.addSubResult(new AqResultBuilder().setDatabaseError(databaseError, sObjectType).createAqResult());
            }
        }

        return this;
    }

    public AqResultBuilder setDeleteResult(Database.DeleteResult deleteResult, SObjectType sObjectType) {
        return setDeleteResult(deleteResult, sObjectType, null);
    }

    public AqResultBuilder setDeleteResult(Database.DeleteResult deleteResult, SObjectType sObjectType, String scope) {

        this.type = AqResult.RESULT_TYPE_DELETE;
        this.level = AqResult.LEVEL_BUSINESS;
        this.returnValue = deleteResult.getId();
        this.scopeType = AqResult.SCOPE_TYPE_RECORD;

        if (String.isNotBlank(scope)) {
            this.scope = scope;
            if (deleteResult.getId() != null) {
                this.scope += ': ' + deleteResult.getId();
            }
        } else {
            this.scope = deleteResult.getId();
        }

        if (deleteResult.isSuccess()) {
            this.severity = AqResult.SEVERITY_SUCCESS;
        } else {
            this.severity = AqResult.SEVERITY_ERROR;
            this.message = DELETE_ERROR_MESSAGE;
            for (Database.Error databaseError : deleteResult.getErrors()) {
                this.addSubResult(new AqResultBuilder().setDatabaseError(databaseError, sObjectType).createAqResult());
            }
        }

        return this;
    }

    public AqResultBuilder setUpsertResult(Database.UpsertResult upsertResult, SObjectType sObjectType) {
        return setUpsertResult(upsertResult, sObjectType, null);
    }

    public AqResultBuilder setUpsertResult(Database.UpsertResult upsertResult, SObjectType sObjectType, String scope) {

        this.type = AqResult.RESULT_TYPE_UPSERT;
        this.level = AqResult.LEVEL_BUSINESS;
        this.returnValue = upsertResult.getId();
        this.scopeType = AqResult.SCOPE_TYPE_RECORD;

        if (String.isNotBlank(scope)) {
            this.scope = scope;
            if (upsertResult.getId() != null) {
                this.scope += ': ' + upsertResult.getId();
            }
        } else {
            this.scope = upsertResult.getId();
        }

        if (upsertResult.isSuccess()) {
            this.severity = AqResult.SEVERITY_SUCCESS;
            if (upsertResult.isCreated()) {
                this.code = AqResult.CODE_CREATED;
            } else {
                this.code = AqResult.CODE_UPDATED;
            }
        } else {
            this.severity = AqResult.SEVERITY_ERROR;
            this.message = UPSERT_ERROR_MESSAGE;
            for (Database.Error databaseError : upsertResult.getErrors()) {
                this.addSubResult(new AqResultBuilder().setDatabaseError(databaseError, sObjectType).createAqResult());
            }
        }

        return this;
    }

    public AqResultBuilder setDatabaseError(Database.Error databaseError, SObjectType sObjectType) {

        this.type = AqResult.RESULT_TYPE_DATABASE_ERROR;
        this.severity = AqResult.SEVERITY_ERROR;
        this.level = AqResult.BUSINESS_STATUS_CODES.contains(databaseError.getStatusCode()) ? AqResult.LEVEL_BUSINESS : AqResult.LEVEL_INTERNAL;
        this.message = databaseError.getMessage();
        this.code = String.valueOf(databaseError.getStatusCode());

        //Convert codes to better messages
        if ((databaseError.getStatusCode() == StatusCode.DUPLICATES_DETECTED || databaseError.getStatusCode() == StatusCode.DUPLICATE_VALUE) && sObjectType != null) {
            this.message = AqString.format(Label.Aq_M_DuplicateFound, sObjectType);
        }

        if (databaseError.getFields() != null) {
            this.scopeType = AqResult.SCOPE_TYPE_FIELD;
            this.scope = String.join(databaseError.getFields(), ',');
        }

        return this;
    }

    public AqResultBuilder setSendEmailResult(Messaging.SendEmailResult emailResult, String scope) {

        this.type = AqResult.RESULT_TYPE_EMAIL;
        this.level = AqResult.LEVEL_BUSINESS;

        if (!String.isEmpty(scope)) {
            this.scopeType = AqResult.SCOPE_TYPE_EMAIL;
            this.scope = scope;
        }

        if (emailResult.isSuccess()) {
            this.severity = AqResult.SEVERITY_SUCCESS;
        } else {
            this.severity = AqResult.SEVERITY_ERROR;
            this.message = EMAIL_ERROR_MESSAGE;
            for (Messaging.SendEmailError sendEmailError : emailResult.getErrors()) {
                this.addSubResult(new AqResultBuilder().setSendEmailError(sendEmailError).createAqResult());
            }
        }

        return this;
    }

    public AqResultBuilder setSendEmailError(Messaging.SendEmailError sendEmailError) {

        this.type = AqResult.RESULT_TYPE_EMAIL_ERROR;
        this.severity = AqResult.SEVERITY_ERROR;
        this.level = AqResult.BUSINESS_STATUS_CODES.contains(sendEmailError.getStatusCode()) ? AqResult.LEVEL_BUSINESS : AqResult.LEVEL_INTERNAL;
        this.message = sendEmailError.getMessage();
        this.code = String.valueOf(sendEmailError.getStatusCode());
        this.scopeType = AqResult.SCOPE_TYPE_EMAIL;
        this.scope = sendEmailError.getTargetObjectId();

        if (sendEmailError.getFields() != null) {
            this.scope = String.join(sendEmailError.getFields(), ',');
        }

        return this;
    }

    public AqResultBuilder setType(String type) {
        if (String.isNotBlank(type)) {
            this.type = type;
        }

        return this;
    }

    public AqResultBuilder setType(Type type) {
        if (type != null) {
            this.type = type.getName();
        }

        return this;
    }

    public AqResultBuilder setSeverity(String severity) {
        if (String.isNotBlank(severity)) {
            this.severity = severity;
        }

        return this;
    }

    public AqResultBuilder setSource(String source) {
        if (String.isNotBlank(source)) {
            this.source = source;
        }

        return this;
    }

    public AqResultBuilder setCode(String code) {
        if (String.isNotBlank(code)) {
            this.code = code;
        }

        return this;
    }

    public AqResultBuilder setLevel(String level) {
        if (String.isNotBlank(level)) {
            this.level = level;
        }

        return this;
    }

    public AqResultBuilder setMessage(String message) {
        if (String.isNotBlank(message)) {
            this.message = message;
        }

        return this;
    }

    public AqResultBuilder setScopeType(String scopeType) {
        if (String.isNotBlank(scopeType)) {
            this.scopeType = scopeType;
        }

        return this;
    }

    public AqResultBuilder setScope(String scope) {
        if (String.isNotBlank(scope)) {
            this.scope = scope;
        }

        return this;
    }

    public AqResultBuilder setDetail(Object detail) {
        if (detail != null) {
            this.detail = detail;
        }

        return this;
    }

    public AqResultBuilder setResultDate(Datetime resultDate) {
        if (resultDate != null) {
            this.resultDate = resultDate;
        }

        return this;
    }

    public AqResultBuilder setReturnValue(Object returnValue) {
        if (returnValue != null) {
            this.returnValue = returnValue;
        }

        return this;
    }

    public AqResultBuilder addSubResults(List<AqResult> subResults) {
        if (this.subResults != null) {
            this.subResults.addAll(subResults);
        } else {
            this.subResults = subResults;
        }

        return this;
    }

    private void addSubResult(AqResult res) {
        if (this.subResults == null) {
            this.subResults = new List<AqResult>();
        }
        this.subResults.add(res);
    }
}
