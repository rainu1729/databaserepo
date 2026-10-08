--------------------------------------------------------
--  DDL for Function CALCULATE_ANNUAL_SALARY
--------------------------------------------------------

  CREATE OR REPLACE FUNCTION "HR"."CALCULATE_ANNUAL_SALARY" 
(p_salary IN NUMBER, p_commission_pct IN NUMBER DEFAULT 0)
RETURN NUMBER AS
BEGIN
  RETURN (NVL(p_salary, 0) * 12) + (NVL(p_salary, 0) * 12 * NVL(p_commission_pct, 0));
END;
/
