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
 * @description Trigger and domain methods for test object, used only for unit test coverage for Aq framework.
 * @group apex/core
**/
public inherited sharing class AqObjAqTestObject extends AqObj {

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Testing

    //These control trigger behavior to allow testing
    public static List<String> Operations = new List<String>();
    public static Boolean FailRequirement = false;
    public static SObjectField RequiredField = null;
    public static Set<SObjectField> RequiredFields = null;
    public static Set<SObjectField> RequiredTogether = null;
    public static SObjectField ValidateStringField = null;
    public static String ValidateStringDatatype = null;
    public static Boolean ValidateStringRequired = null;
    public static Integer ValidateStringLength = null;
    public static SObjectField ValidatePatternField = null;
    public static Boolean ValidatePatternRequired = null;
    public static String ValidatePatternRegex = null;
    public static String ValidatePatternLabel = null;
    public static SObjectField ValidateIntegerField = null;
    public static Boolean ValidateIntegerRequired = null;
    public static Integer ValidateIntegerMin = null;
    public static Integer ValidateIntegerMax = null;
    public static Boolean CaptureChangedFields = false;
    public static List<Set<SObjectField>> ChangedFields = new List<Set<SObjectField>>();
    public static Set<SObjectField> ChangedAnyFields = null;
    public static SObjectField ChangedFromToField = null;
    public static object ChangedFromValue = null;
    public static object ChangedToValue = null;
    public static Boolean IsChangedAnyFields = null;
    public static Boolean IsChangedFrom = null;
    public static Boolean IsChangedTo = null;
    public static Boolean IsChangedToNonNull = null;
    public static List<sObject> oldRecords = null;
    public static sObject oldRecord = null;
    public static object oldValue = null;

    public static void clearOperations() {
        Operations.clear();
        ChangedFields.clear();
        FailRequirement = false;
        RequiredField = null;
        RequiredFields = null;
        RequiredTogether = null;
        CaptureChangedFields = false;
        ValidateStringField = null;
        ValidateStringDatatype = null;
        ValidateStringRequired = null;
        ValidateStringLength = null;
        ValidatePatternField = null;
        ValidatePatternRequired = null;
        ValidatePatternRegex = null;
        ValidatePatternLabel = null;
        ValidateIntegerField = null;
        ValidateIntegerRequired = null;
        ValidateIntegerMin = null;
        ValidateIntegerMax = null;
        ChangedAnyFields = null;
        ChangedFromToField = null;
        ChangedFromValue = null;
        ChangedToValue = null;
        IsChangedAnyFields = null;
        IsChangedFrom = null;
        IsChangedTo = null;
        IsChangedToNonNull = null;
        oldRecords = null;
        oldRecord = null;
        oldValue = null;
    }

    public void recordChangedFields(TestObject__c record) {

        Set<SObjectField> recordChangedFields = new Set<SObjectField>();
        for (SObjectField field : TestObject__c.sObjectType.getDescribe().fields.getMap().values()) {
            if (field.getDescribe().isCustom() && isChangedField(record, field))
                recordChangedFields.add(field);
        }
        ChangedFields.add(recordChangedFields);

    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Constants

    //Record types
    public static final String RECORD_TYPE_1 = 'RecordType1';
    public static final String RECORD_TYPE_2 = 'RecordType2';

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Trigger methods

    //Validate before any calculation is done -- to validate any values that must be correct before any calculation
    protected override void preValidate(List<sObject> records) {
        Operations.add('preValidate');
        oldRecords = oldRecords();
        oldRecord = oldRecord(records[0]);
        oldValue = oldValue(records[0], TestObject__c.RequiredText__c);
    }

    //Do any pre-delete validation to potentially prevent deletion
    protected override void preValidateDelete(List<sObject> records) {

        Operations.add('preValidateDelete');
        if (CaptureChangedFields == true)
            for (TestObject__c record : (List<TestObject__c>)records)
                recordChangedFields(record);

        oldRecords = oldRecords();
        oldRecord = oldRecord(records[0]);
        oldValue = oldValue(records[0], TestObject__c.RequiredText__c);

    }

    //Initialize values on a new record
    protected override void initialize(List<sObject> records) {
        Operations.add('initialize');
    }

    //Calculate values on a new or updated record
    protected override void calculate(List<sObject> records) {

        Operations.add('calculate');

        if (ChangedAnyFields != null)
            IsChangedAnyFields = isChangedAnyField(records[0], ChangedAnyFields);

        if (ChangedFromToField != null) {

            IsChangedFrom = isChangedFieldFrom(records[0], ChangedFromToField, ChangedFromValue);
            IsChangedTo = isChangedFieldTo(records[0], ChangedFromToField, ChangedToValue);
            IsChangedToNonNull = isChangedFieldToNonNull(records[0], ChangedFromToField);

        }

    }

    //Validate all values after calculations have taken place
    protected override void validate(List<sObject> records) {

        Operations.add('validate');

        for (TestObject__c record : (List<TestObject__c>)records) {

            if (CaptureChangedFields == true)
                recordChangedFields(record);

            if (FailRequirement == true)
                require(record, null, false, 'Failed');

            if (RequiredField != null)
                requireField(record, RequiredField);

            if (RequiredFields != null)
                requireFields(record, RequiredFields);

            if (RequiredTogether != null)
                requireTogether(record, RequiredTogether);

            if (ValidateStringField != null) {
                if (ValidateStringLength != null)
                    validateString(record, ValidateStringField, ValidateStringDatatype, ValidateStringRequired, ValidateStringLength);
                else if (ValidateStringRequired != null)
                    validateString(record, ValidateStringField, ValidateStringDatatype, ValidateStringRequired);
                else
                    validateString(record, ValidateStringField, ValidateStringDatatype);

            }

            if (ValidatePatternField != null) {
                validatePattern(record, ValidatePatternField, ValidatePatternRequired, ValidatePatternRegex, ValidatePatternLabel);
            }

            if (ValidateIntegerField != null) {
                validateInteger(record, ValidateIntegerField, ValidateIntegerRequired, ValidateIntegerMin, ValidateIntegerMax);
            }

        }

    }

    //Do any processing that should happen only after insert (but not after update or delete)
    protected override void postInsert(List<sObject> records) {
        Operations.add('postInsert');
    }

    //Do any processing that should happen only after update (but not after insert or delete)
    protected override void postUpdate(List<sObject> records) {
        Operations.add('postUpdate');
    }

    //Do any processing that should happen after insert OR update (but not after delete)
    protected override void postUpsert(List<sObject> records) {
        Operations.add('postUpsert');
    }

    //Do any processing that should happen after delete
    protected override void postDelete(List<sObject> records) {
        Operations.add('postDelete');
    }

}
