@SuppressWarnings('PMD')
public inherited sharing abstract class TriggerHandler {
    //Entry method called from the trigger itself
    public virtual void onTrigger() {
        if (Trigger.isBefore) {
            if (Trigger.isInsert) {
                beforeInsert(Trigger.new);
                beforeUpsert(Trigger.new);
            } else if (Trigger.isUpdate) {
                beforeUpdate(Trigger.new);
                beforeUpsert(Trigger.new);
            } else if (Trigger.isDelete) {
                beforeDelete(Trigger.old);
            }
        } else if (Trigger.isAfter) {
            if (isInsert()) {
                afterInsert(Trigger.new);
                afterUpsert(Trigger.new);
            } else if (isUpdate()) {
                afterUpdate(Trigger.new);
                afterUpsert(Trigger.new);
            } else if (isDelete()) {
                afterDelete(Trigger.old);
            }
        }
    }

    protected virtual void beforeInsert(List<sObject> records) {
    }

    protected virtual void beforeUpdate(List<sObject> records) {
    }

    protected virtual void beforeUpsert(List<sObject> records) {
    }

    protected virtual void beforeDelete(List<sObject> records) {
    }

    protected virtual void afterInsert(List<sObject> records) {
    }

    protected virtual void afterUpdate(List<sObject> records) {
    }

    protected virtual void afterUpsert(List<sObject> records) {
    }

    protected virtual void afterDelete(List<sObject> records) {
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
}
