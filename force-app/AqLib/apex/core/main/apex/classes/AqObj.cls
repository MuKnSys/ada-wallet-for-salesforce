/*
 * Copyright (c) 2020, Aquiva Labs LLC. All rights reserved.
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
 * @description Trigger framework and base class for all standard and custom object classes.
 * 
 * @group apex/core
 */
public inherited sharing abstract class AqObj {

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Triggers method

    // @start-group Public methods

    /**
     * @description Entry method called from the trigger itself
     * Extend your SObject trigger handler class from <<AqObj>> (e.g. AccountObj).
     * Create the corresponding `.trigger` class and call [onTrigger()](#public-virtual-void-ontrigger) method.
     * All the protected triggers methods mentioned below gets [TriggerRecords](#protected-triggerrecords--listsobject) list as a parameter.
     * `Account.trigger`:
     *
     * @example
     * trigger Account on Account (before insert, before update, after update) {
     *       new AccountObj().onTrigger();
     * }
     * //
     * // In your handler, override required protected trigger method (`preValidateDelete()` |
     * // `preValidate()` | `initialize()` | `calculate()` | `validate()` |
     * // `postInsertUpsertDelete()` | `postInsert()` | `postUpsert()` | `postUpdate()` | `postDelete()`)
     * // and put your trigger logic inside, e.g.:
     * //
     * protected override void postUpdate(List<SObject> records) {
     *      this.updateAccountFields(records);
     * }
     *
     */
    public virtual void onTrigger() {

        if (Trigger.isBefore) {

            if (Trigger.isDelete) {

                preValidateDelete(this.TriggerRecords);
            } else {

                preValidate(this.TriggerRecords);

                if (Trigger.isInsert) {
                    initialize(this.TriggerRecords);
                }
                calculate(this.TriggerRecords);
                validate(this.TriggerRecords);
            }
        } else if (Trigger.isAfter) {

            postInsertUpsertDelete(this.TriggerRecords);

            if (Trigger.isInsert || Trigger.isUndelete) {
                postInsert(this.TriggerRecords);
                postUpsert(this.TriggerRecords);
            }
            else if (Trigger.isUpdate) {
                postUpdate(this.TriggerRecords);
                postUpsert(this.TriggerRecords);
            }
            else if (Trigger.isDelete) {
                postDelete(this.TriggerRecords);
            }
        }
    }
    // @end-group

    // @start-group Protected triggers methods

    /**
     * @description Validate before any calculation is done -- to validate any values that must be correct before any calculation
     */
    protected virtual void preValidate(List<sObject> records) {}

    /**
	* @description Do any pre-delete validation to potentially prevent deletion
	*/
    protected virtual void preValidateDelete(List<sObject> records) {}

    /**
	* @description Initialize values on a new record
	*/
    protected virtual void initialize(List<sObject> records) {}

    /**
	* @description Calculate values on a new or updated record
	*/
    protected virtual void calculate(List<sObject> records) {}

    /**
	* @description Validate all values after calculations have taken place
	*/
    protected virtual void validate(List<sObject> records) {}

    /**
	* @description Do any processing that should happen only after insert (but not after update or delete)
	*/
    protected virtual void postInsert(List<sObject> records) {}

    /**
	* @description Do any processing that should happen only after update (but not after insert or delete)
	*/
    protected virtual void postUpdate(List<sObject> records) {}

    /**
	* @description Do any processing that should happen after insert OR update (but not after delete)
	*/
    protected virtual void postUpsert(List<sObject> records) {}

    /**
	* @description Do any processing that should happen after delete
	*/
    protected virtual void postDelete(List<sObject> records) {}

    /**
	* @description Do any processing that should happen after insert, update, or delete
	*/
    protected virtual void postInsertUpsertDelete(List<sObject> records) {}

    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Trigger Abstractions

    /**
	* @description Handling of errors within this instance
	*/
    private Set<Id> erroredIds = new Set<Id>();
    private List<sObject> erroredRecords = new List<sObject>();
    private List<sObject> triggerRecordsOverride = null;


    /**
	* @description Returns relevant set of records for processing in the trigger
	* This includes management of errored records within the same instantiation, so that 
    * error records aren't presented to methods for downstream processing.
	*/
    protected List<SObject> TriggerRecords {

        get {

            List<sObject> baseRecords = this.isDelete() ? trigger.old : trigger.new;

            if (triggerRecordsOverride != null) {
                return triggerRecordsOverride;
            } else if (!erroredRecords.isEmpty()) {

                triggerRecordsOverride = new List<sObject>();
                for (sObject baseRecord : baseRecords) {

                    if (baseRecord.Id != null) {
                        if (!erroredIds.contains(baseRecord.Id)) {
                            triggerRecordsOverride.add(baseRecord);
                        }
                    } else {

                        //New record without an ID, have to compare objects using ===
                        //Cannot use Set<sObject> because it compares using ==
                        Boolean isError = false;
                        for (sObject erroredRecord : erroredRecords){
                            if (baseRecord === erroredRecord) {
                                isError = true;
                                break;
                            }
                        }

                        if (!isError){
                            triggerRecordsOverride.add(baseRecord);
                        }
                    }
                }

                erroredRecords.clear();
                return triggerRecordsOverride;
            } else {
                return baseRecords;
            }
        }
    }

    // @start-group Protected auxiliary methods

    /**
	* @description Add error to a record
	*/
    protected void addError(sObject record, sObjectField field, String errorString) {
        record.addError(errorString);
        if (record.Id != null) {
            erroredIds.add(record.Id);
        }
        erroredRecords.add(record);
    }

    protected Boolean isInsert() {
        return Trigger.isInsert;
    }

    protected Boolean isUpdate() {
        return Trigger.isUpdate;
    }

    protected Boolean isDelete() {
        return Trigger.isDelete;
    }

    protected Boolean isUndelete() {
        return Trigger.isUndelete;
    }

    /**
	* @description Return old records
	*/
    protected List<sObject> oldRecords() {
        if (isUpdate() || isDelete()) {
            return Trigger.old;
        } else {
            return null;
        }
    }

    /**
	* @description Return old record
	*/
    protected sObject oldRecord(sObject record) {
        if (isUpdate() || isDelete()) {
            return Trigger.oldMap.get(record.Id);
        } else {
            return null;
        }
    }

    /**
	* @description Return old field value
	*/
    protected object oldValue(sObject record, sObjectField field) {

        if (isUpdate() || isDelete()) {
            return oldRecord(record).get(field);
        } else {
            return null;
        }
    }

    /**
	* @description Return old records 
	*/
    protected Map<Id, sObject> getOldMap() {
        if (isUpdate() || isDelete()) {
            return Trigger.oldMap;
        }
        return null;
    }

    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Validation

    // @start-group Protected validation methods
    /**
	* @description Works like an assert to add error if condition is not met
	*/
    protected void require(sObject record, sObjectField field, Boolean condition, String errorMessage) {
        if (condition != true) {
            addError(record, field, errorMessage);
        }
    }

    /**
	* @description True if field has no value
	*/
    private Boolean fieldIsEmpty(sObject record, sObjectField field) {
        object value = record.get(field);
        if (value == null) {
            return true;
        } else if (value instanceof String) {
            return String.isEmpty((String)value);
        } else {
            return false;
        }
    }

    /**
	* @description Required the record to have values set on all specified fields
	*/
    protected void requireFields(sObject record, Set<sObjectField> fields) {

        List<sObjectField> missingFields = new List<sObjectField>();
        for (sObjectField field : new List<sObjectField>(fields)){
            if (fieldIsEmpty(record, field)) {
                missingFields.add(field);
            }
        }

        if (missingFields.size() == 1) {
            addError(record, null, AqString.format(Label.Aq_M_ValueRequired, missingFields[0]));
        } else if (missingFields.size() > 1) {
            addError(record, null, AqString.format(Label.Aq_M_ValuesRequired, AqString.formatList(missingFields)));
        }
    }

    /**
	* @description Required the record to have values set on the specified field
	*/
    protected void requireField(sObject record, sObjectField field) {

        if (fieldIsEmpty(record, field)) {
            addError(record, field, AqString.format(Label.Aq_M_ValueRequired, field));
        }
    }

    /**
	* @description If any are not-null, then all must be not-null
	*/
    protected void requireTogether(sObject record, Set<SObjectField> fields) {

        Boolean oneSpecified = false;
        for (SObjectField field : fields) {
            if (!fieldIsEmpty(record, field)) {
                oneSpecified = true;
                break;
            }
        }

        if (!oneSpecified) {
            return;
        }

        for (SObjectField field : fields) {
            if (fieldIsEmpty(record, field)) {
                addError(record, field, AqString.format(Label.Aq_M_RequiredTogether, AqString.formatSet(fields)));
            }
        }
    }

    /**
	* @description Validate a string against specified type
	*/
    protected void validateString(sObject record, sObjectField field, String dataType, Boolean required, Integer maxLength) {

        AqResult result = AqTypes.validateAndConvert(
            'Field', AqString.valueOf(field), dataType,
            String.valueOf(record.get(field)), required, maxLength
        );
        if (result.hasError()) {
            addError(record, field, result.Message);
        }
    }

    /**
	* @description Validate a string against specified type
	*/
    protected void validateString(sObject record, sObjectField field, String dataType, Boolean required) {
        validateString(record, field, dataType, required, null);
    }

    /**
	* @description Validate a string against specified type
	*/
    protected void validateString(sObject record, sObjectField field, String dataType) {
        validateString(record, field, dataType, false, null);
    }

    /**
	* @description Validate a string to meet specified pattern
	*/
    protected void validatePattern(sObject record, sObjectField field, Boolean required, String regEx, String patternLabel) {
        AqResult result = AqTypes.validatePattern('Field', AqString.valueOf(field), String.valueOf(record.get(field)), required, regEx, patternLabel);
        if (result.hasError()) {
            addError(record, field, result.Message);
        }
    }

    /**
	* @description Validate an integer for range
	*/
    protected void validateInteger(sObject record, sObjectField field, Boolean required, Integer min, Integer max) {

        if (required == true) {
            requireField(record, field);
        }

        Integer value = Integer.valueOf(record.get(field));
        if (value != null) {

            if (min != null && value < min) {
                addError(record, field, AqString.format(Label.Aq_M_ValueLessThanMin, value, min));
            } else if (max != null && value > max) {
                addError(record, field, AqString.format(Label.Aq_M_ValueGreaterThanMax, value, max));
            }
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /**
	* @description Change detection
	* Returns true if field is changed in this trigger context
	*/
    protected Boolean isChangedField(sObject record, sObjectField field) {

        if (isInsert() || isUndelete()) {
            return record.get(field) != null;
        } else if (isDelete()) {
            return Trigger.oldMap.get(record.Id).get(field) != null;
        } else if (isUpdate()) {
            return record.get(field) != Trigger.oldMap.get(record.Id).get(field);
        } else {
            return false;
        }
    }

    /**
	* @description Returns true if any specified field is changed in this trigger context
	*/
    protected Boolean isChangedAnyField(sObject record, Set<sObjectField> fields) {

        for (sObjectField field : fields) {
            if (isChangedField(record, field)) {
                return true;
            }
        }
        return false;
    }


    /**
	* @description Returns true if field changed from specified value to some other value
	*/
    protected Boolean isChangedFieldFrom(sObject record, sObjectField field, object fromValue) {
        return oldValue(record, field) == fromValue && isChangedField(record, field);
    }

    /**
	* @description Returns true if field changed to specified value
	*/
    protected Boolean isChangedFieldTo(sObject record, sObjectField field, object toValue) {
        return isChangedField(record, field) && record.get(field) == toValue;
    }

    /**
	* @description Returns true if field changed and to a non-null value
	*/
    protected Boolean isChangedFieldToNonNull(sObject record, sObjectField field) {
        return isChangedField(record, field) && record.get(field) != null;
    }

    // @end-group
}
