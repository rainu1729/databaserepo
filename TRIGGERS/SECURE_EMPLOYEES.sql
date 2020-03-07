--------------------------------------------------------
--  DDL for Trigger SECURE_EMPLOYEES
--------------------------------------------------------

  CREATE OR REPLACE TRIGGER "HR"."SECURE_EMPLOYEES" 
  BEFORE INSERT OR UPDATE OR DELETE ON employees
BEGIN
--SAMPLE TRIGGER TEST AGAIN
  secure_dml;
END secure_employees;
--new line
/
ALTER TRIGGER "HR"."SECURE_EMPLOYEES" DISABLE;
