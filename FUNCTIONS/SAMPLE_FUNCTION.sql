--------------------------------------------------------
--  DDL for Function SAMPLE_FUNCTION
--------------------------------------------------------

  CREATE OR REPLACE FUNCTION "HR"."SAMPLE_FUNCTION" 
(v_in in number)
return varchar2 as
begin
return v_in+2;
end;
--added sample lines
/
