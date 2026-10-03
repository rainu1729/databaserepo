--------------------------------------------------------
--  Deferred Foreign Keys
--  These constraints reference tables created later in
--  the deployment order (circular dependencies).
--------------------------------------------------------

  ALTER TABLE "HR"."DEPARTMENTS" ADD CONSTRAINT "DEPT_MGR_FK" FOREIGN KEY ("MANAGER_ID")
	  REFERENCES "HR"."EMPLOYEES" ("EMPLOYEE_ID") ENABLE;
