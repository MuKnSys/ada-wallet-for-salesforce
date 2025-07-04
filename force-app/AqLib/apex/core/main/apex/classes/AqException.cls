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
 * @description Base custom exception
 * @group apex/core
 */
public inherited sharing virtual class AqException extends System.Exception {

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Properties

    //Exception is based on AqResult values
    public AqResult Result = new AqResultBuilder()
        .setSeverity(AqResult.SEVERITY_ERROR)
        .setLevel(AqResult.LEVEL_BUSINESS)
        .createAqResult();

    /**
     * @description Identifies the type of data that the exception applies to
     */
    public String ScopeType {
        get {
            return this.Result.ScopeType;
        }
        set {
            this.Result.ScopeType = value;
        }
    }

    /**
     * @description Identifies the data that the exception applies to
     */
    public String Scope {
        get {
            return this.Result.Scope;
        }
        set {
            this.Result.Scope = value;
        }
    }

    /**
     * @description Invariant code for the exception that can be used to identify a specific exception condition.
     */
    public String Code {
        get {
            return this.Result.Code;
        }
        set {
            this.Result.Code = value;
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Constructors

    /**
     * @description Construct exception from result
     */
    public AqException(AqResult result) {
        this.Result = result;
        this.setMessage(result.Message);
        if (Test.isRunningTest() && String.isEmpty(result.Message)) {
            this.setMessage(AqJson.stripNulls(JSON.serialize(result), true));
        }
    }

    /**
     * @description Construct from values
     */
    public AqException(String code, String scopeType, String scope) {
        this.Code = code;
        this.ScopeType = scopeType;
        this.Scope = scope;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Methods

    /**
     * @description Return serializable detail specific to the exception type.
     */
    public virtual ExceptionDetail getDetail() {
        return new ExceptionDetail(this);
    }

    /**
     * @description Return serializable detail for any exception.
     */
    public static ExceptionDetail getExceptionDetail(System.Exception e) {
        if (e instanceof AqException) {
            return ((AqException)e).getDetail();
        }
    
        return new ExceptionDetail(e);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Nested classes

    /**
     * @description Serializable class holding exception detail beyond the message.
     */
    public virtual class ExceptionDetail {

        public Integer LineNumber { get; set; }
        public String StackTrace { get; set; }

        public ExceptionDetail(System.Exception e) {
            this.LineNumber = e.getLineNumber();
            this.StackTrace = e.getStackTraceString();
        }

    }

    /**
     * @description Serializable exception information for one DML row
     */
    public class DmlRowDetail {

        public Integer RowIndex { get; set; }
        public List<String> FieldNames { get; set; }
        public String RecordId { get; set; }
        public String Message { get; set; }
        public String Type { get; set; }

        /**
         * @description Construct from DmlException row
         */
        public DmlRowDetail(System.DmlException e, Integer rowDetailNum) {
            this.RowIndex = e.getDmlIndex(rowDetailNum);
            this.FieldNames = e.getDmlFieldNames(rowDetailNum);
            this.RecordId = e.getDmlId(rowDetailNum);
            this.Message = e.getDmlMessage(rowDetailNum);
            this.Type = String.valueOf(e.getDmlType(rowDetailNum));
        }

        /**
         * @description Construct from EmailException row
         */
        public DmlRowDetail(System.EmailException e, Integer rowDetailNum) {
            this.RowIndex = e.getDmlIndex(rowDetailNum);
            this.FieldNames = e.getDmlFieldNames(rowDetailNum);
            this.RecordId = e.getDmlId(rowDetailNum);
            this.Message = e.getDmlMessage(rowDetailNum);
            this.Type = String.valueOf(e.getDmlType(rowDetailNum));
        }

    }

}
