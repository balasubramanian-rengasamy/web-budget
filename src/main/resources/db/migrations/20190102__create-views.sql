-- view 001
CREATE OR REPLACE VIEW financial.wb_view_001 AS
SELECT row_number() OVER () AS id,
       fp.identification AS financial_period,
       mc.movement_class_type AS direction,
       cc.id AS cost_center_id,
       cc.name AS cost_center,
       COALESCE(sum(pa.paid_value), 0::numeric) AS total_value
FROM financial.movements pm
       JOIN registration.financial_periods fp ON fp.id = pm.id_financial_period
       JOIN financial.apportionments ap ON ap.id_movement = pm.id
       JOIN registration.cost_centers cc ON cc.id = ap.id_cost_center
       JOIN registration.movement_classes mc ON mc.id = ap.id_movement_class
       JOIN financial.payments pa ON pa.id = pm.id_payment AND fp.closed = false AND pm.id_credit_card_invoice IS NULL AND pm.discriminator_value::text = 'PERIOD_MOVEMENT'::text
GROUP BY fp.identification, cc.id, cc.name, mc.movement_class_type;

COMMENT ON VIEW financial.wb_view_001 IS 'List by the open financial periods all cost centers and the respective value spent or received in each one';

-- view 002
CREATE OR REPLACE VIEW financial.wb_view_002 AS
SELECT row_number() OVER () AS id,
       fp.identification AS financial_period,
       mc.movement_class_type AS direction,
       cc.id AS cost_center_id,
       cc.name AS cost_center,
       mc.id AS movement_class_id,
       mc.name AS movement_class,
       COALESCE(sum(pa.paid_value), 0::numeric) AS total_value
FROM financial.movements pm
       JOIN registration.financial_periods fp ON fp.id = pm.id_financial_period
       JOIN financial.apportionments ap ON ap.id_movement = pm.id
       JOIN registration.cost_centers cc ON cc.id = ap.id_cost_center
       JOIN registration.movement_classes mc ON mc.id = ap.id_movement_class
       JOIN financial.payments pa ON pa.id = pm.id_payment AND fp.closed = false AND pm.id_credit_card_invoice IS NULL AND pm.discriminator_value::text = 'PERIOD_MOVEMENT'::text
GROUP BY fp.identification, cc.id, cc.name, mc.id, mc.name, mc.movement_class_type;

COMMENT ON VIEW financial.wb_view_002 IS 'List by the open financial periods all movement classes and the value spent or received in each one';

-- view 003
CREATE OR REPLACE VIEW financial.wb_view_003 AS
  WITH revenues_total AS (
    SELECT COALESCE(sum(pm.paid_value), 0::numeric) AS revenues
    FROM financial.movements mv
           JOIN financial.apportionments ap ON ap.id_movement = mv.id
           JOIN financial.payments pm ON pm.id = mv.id_payment
           JOIN registration.financial_periods fp ON fp.id = mv.id_financial_period
           JOIN registration.movement_classes mc ON mc.id = ap.id_movement_class AND fp.closed = false AND mv.discriminator_value::text = 'PERIOD_MOVEMENT'::text AND mc.movement_class_type::text = 'REVENUE'::text
  ), expenses_total AS (
    SELECT COALESCE(sum(pm.paid_value), 0::numeric) AS expenses
    FROM financial.movements mv
           JOIN financial.apportionments ap ON ap.id_movement = mv.id
           JOIN financial.payments pm ON pm.id = mv.id_payment
           JOIN registration.financial_periods fp ON fp.id = mv.id_financial_period
           JOIN registration.movement_classes mc ON mc.id = ap.id_movement_class AND fp.closed = false AND mv.id_credit_card_invoice IS NULL AND mv.discriminator_value::text = 'PERIOD_MOVEMENT'::text AND mc.movement_class_type::text = 'EXPENSE'::text
  ), credit_card_expenses_total AS (
    SELECT COALESCE(sum(pm.paid_value), 0::numeric) AS credit_card_expenses
    FROM financial.movements mv
           JOIN financial.apportionments ap ON ap.id_movement = mv.id
           JOIN financial.payments pm ON pm.id = mv.id_payment
           JOIN registration.financial_periods fp ON fp.id = mv.id_financial_period
           JOIN registration.movement_classes mc ON mc.id = ap.id_movement_class AND fp.closed = false AND pm.payment_method::text = 'CREDIT_CARD'::text AND mv.discriminator_value::text = 'PERIOD_MOVEMENT'::text AND mc.movement_class_type::text = 'EXPENSE'::text
  ), debit_card_expenses_total AS (
    SELECT COALESCE(sum(pm.paid_value), 0::numeric) AS debit_card_expenses
    FROM financial.movements mv
           JOIN financial.apportionments ap ON ap.id_movement = mv.id
           JOIN financial.payments pm ON pm.id = mv.id_payment
           JOIN registration.financial_periods fp ON fp.id = mv.id_financial_period
           JOIN registration.movement_classes mc ON mc.id = ap.id_movement_class AND fp.closed = false AND pm.payment_method::text = 'DEBIT_CARD'::text AND mv.discriminator_value::text = 'PERIOD_MOVEMENT'::text AND mc.movement_class_type::text = 'EXPENSE'::text
  ), cash_expenses_total AS (
    SELECT COALESCE(sum(pm.paid_value), 0::numeric) AS cash_expenses
    FROM financial.movements mv
           JOIN financial.apportionments ap ON ap.id_movement = mv.id
           JOIN financial.payments pm ON pm.id = mv.id_payment
           JOIN registration.financial_periods fp ON fp.id = mv.id_financial_period
           JOIN registration.movement_classes mc ON mc.id = ap.id_movement_class AND fp.closed = false AND pm.payment_method::text = 'CASH'::text AND mv.discriminator_value::text = 'PERIOD_MOVEMENT'::text AND mc.movement_class_type::text = 'EXPENSE'::text
  ), total_movements_open AS (
    SELECT COALESCE(sum(mv.value), 0::numeric) AS movements_open
    FROM financial.movements mv
           JOIN financial.apportionments ap ON ap.id_movement = mv.id
           JOIN registration.financial_periods fp ON fp.id = mv.id_financial_period
           JOIN registration.movement_classes mc ON mc.id = ap.id_movement_class AND fp.closed = false AND mv.period_movement_state::text = 'OPEN'::text AND mv.discriminator_value::text = 'PERIOD_MOVEMENT'::text AND mc.movement_class_type::text = 'EXPENSE'::text
  ), balance AS (
    SELECT COALESCE(rt.revenues, 0::numeric) - COALESCE(et.expenses, 0::numeric) AS balance
    FROM revenues_total rt,
         expenses_total et
  ), period_goal AS (
    SELECT COALESCE(sum(fp.credit_card_goal), 0::numeric) AS credit_card_goal,
           COALESCE(sum(fp.revenues_goal), 0::numeric) AS revenues_goal,
           COALESCE(sum(fp.expenses_goal), 0::numeric) AS expenses_goal
    FROM registration.financial_periods fp
    WHERE fp.closed = false
  )
  SELECT row_number() OVER () AS id,
         revenues_total.revenues,
         expenses_total.expenses,
         cash_expenses_total.cash_expenses,
         credit_card_expenses_total.credit_card_expenses,
         debit_card_expenses_total.debit_card_expenses,
         total_movements_open.movements_open,
         balance.balance,
         period_goal.credit_card_goal,
         period_goal.revenues_goal,
         period_goal.expenses_goal
  FROM revenues_total,
       expenses_total,
       cash_expenses_total,
       credit_card_expenses_total,
       debit_card_expenses_total,
       total_movements_open,
       balance,
       period_goal;

COMMENT ON VIEW financial.wb_view_003 IS 'Quick resume of the open financial periods';

-- view 004
CREATE OR REPLACE VIEW financial.wb_view_004 AS
SELECT row_number() OVER () AS id,
       COALESCE(sum(cl.revenues), 0::numeric) AS revenues_total,
       COALESCE(sum(cl.expenses), 0::numeric) AS expenses_total,
       COALESCE(sum(cl.credit_card_expenses), 0::numeric) AS credit_card_expenses,
       COALESCE(sum(cl.cash_expenses), 0::numeric) AS cash_expenses,
       COALESCE(sum(cl.debit_card_expenses), 0::numeric) AS debit_card_expenses,
       COALESCE(sum(cl.revenues), 0::numeric) - COALESCE(sum(cl.expenses), 0::numeric) AS balance
FROM registration.financial_periods fp
       JOIN financial.closings cl ON cl.id_financial_period = fp.id AND fp.closed = true;

COMMENT ON VIEW financial.wb_view_004 IS 'Quick resume of all closed financial periods';

-- view 005
CREATE OR REPLACE VIEW financial.wb_view_005 AS
SELECT row_number() OVER () AS id,
       fp.id AS financial_period_id,
       fp.identification AS financial_period,
       cl.expenses,
       cl.revenues,
       cl.balance
FROM registration.financial_periods fp
       JOIN financial.closings cl ON cl.id_financial_period = fp.id AND fp.closed = true;

COMMENT ON VIEW financial.wb_view_005 IS 'Result of each closed financial period';
