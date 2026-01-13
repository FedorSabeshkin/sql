
-- total_battles
WITH (SELECT 
    ms.squad_id,
    COUNT(s_b.report_id) total_battles
FROM military_squads ms   
JOIN squad_battles s_b 
				ON s_b.squad_id = ms.squad_id
GROUP BY ms.squad_id) 
	AS battle_amount_table,
	
-- victories
(SELECT 
    ms.squad_id,
    COUNT(s_b.report_id) victories
FROM military_squads ms   
JOIN squad_battles s_b 
				ON s_b.squad_id = ms.squad_id
WHERE s_b.outcome = "WIN" 
GROUP BY ms.squad_id) 
	AS victories_table,

-- current_members
(SELECT 
    s_m.squad_id,
    COUNT(DISTINCT s_m.dwarf_id) current_members
FROM squad_members s_m  
WHERE s_m.exit_reason IS NULL 
GROUP BY s_m.squad_id) 
	AS current_members_table,
	
-- total_members_ever
(SELECT 
    s_m.squad_id,
    COUNT(DISTINCT s_m.dwarf_id) total_members_ever
FROM squad_members s_m 
GROUP BY s_m.squad_id) 
	AS total_members_ever_table,


-- total_training_sessions
(SELECT 
    s_t.squad_id,
    COUNT(s_t.schedule_id) total_training_sessions
FROM squad_training s_t 
GROUP BY s_t.squad_id) 
	AS total_training_sessions_table,
	
-- avg_training_effectiveness
(SELECT 
    s_t.squad_id,
    AVG(s_t.effectiveness) avg_training_effectiveness
FROM squad_training s_t 
GROUP BY s_t.squad_id) 
	AS avg_training_effectiveness_table,


-- casualty rate by date
(SELECT 
    s_b.squad_id,
    s_b.report_id,
	s_b.date,
	s_b.enemy_casualties,
	s_b.casualties,
    COUNT(DISTINCT s_m.dwarf_id) total_members_by_date
FROM squad_battles s_b   
JOIN squad_members s_m 
				ON s_m.squad_id = s_b.squad_id
WHERE s_m.join_date < s_b.date 
			AND s_m.exit_date = s_b.date
GROUP BY s_b.squad_id,
		s_b.report_id, 
		s_b.date,
		s_b.enemy_casualties,
		s_b.casualties) 
	AS casualty_rate_table,
	
-- avg_equipment_quality
(SELECT s_e.squad_id,
		eq.equipment_id,
		AVG(eq.quality * s_e.quantity) avg_equipment_quality
FROM squad_equipment s_e
JOIN equipment eq 
	ON eq.equipment_id = s_e.equipment_id
GROUP BY s_e.squad_id,
		eq.equipment_id, 
) 
	AS avg_equipment_quality_table,
	
-- Минимальная дата (начало периода), крайняя дата выбытия (конец периода)
(SELECT s_m.squad_id,
		MIN(s_m.join_date) start_period,
		MAX(s_m.exit_date) end_period
FROM squad_members s_m
GROUP BY s_m.squad_id
) 
	AS start_end_period_table,
	
-- Число членов отряда в начале и конце периода конкретного отряда (что верно, т.к. один отряд может существовать неделю, а второй 5 лет, и у них надо с разных дат расчитывать удержание.
(SELECT s_m.squad_id,
		COUNT(DISTINCT s_m.dwarf_id) start_period_dwarfs_amount
FROM squad_members s_m
JOIN start_end_period_table s_e_p_t
		ON s_e_p_t.squad_id = s_m.squad_id
WHERE s_m.join_date = s_e_p_t.start_period
GROUP BY s_m.squad_id
) 
	AS start_period_dwarfs_amount_table,

-- end_period_amount
(SELECT s_m.squad_id,
		COUNT(DISTINCT s_m.dwarf_id) end_period_dwarfs_amount
FROM squad_members s_m
JOIN start_end_period_table s_e_p_t
		ON s_e_p_t.squad_id = s_m.squad_id
WHERE s_m.exit_date IS NULL 
GROUP BY s_m.squad_id
) 
	AS end_period_dwarfs_amount_table,


-- added_period_amount
(SELECT s_m.squad_id,
		COUNT(DISTINCT s_m.dwarf_id) added_period_dwarfs_amount
FROM squad_members s_m
JOIN start_end_period_table s_e_p_t
		ON s_e_p_t.squad_id = s_m.squad_id
WHERE s_m.join_date > s_e_p_t.start_period
GROUP BY s_m.squad_id
) 
	AS added_period_dwarfs_amount_table,

-- start_end_added_period_amount

(SELECT s_m.squad_id,
		s_p_d_a.start_period_dwarfs_amount start_amount,
		e_p_d_a.end_period_dwarfs_amount end_amount,
		a_p_d_a.added_period_dwarfs_amount added_amount,
	
		COALESCE((ROUND(( (end_amount - added_amount)::DECIMAL / NULLIF(start_amount, 0)) * 100, 2), 0) AS retention_rate,
	
FROM squad_members s_m
JOIN start_period_dwarfs_amount_table s_p_d_a
		ON s_p_d_a.squad_id = s_m.squad_id
JOIN end_period_dwarfs_amount_table e_p_d_a
		ON e_p_d_a.squad_id = s_m.squad_id
JOIN added_period_dwarfs_amount_table a_p_d_a
		ON a_p_d_a.squad_id = s_m.squad_id
GROUP BY s_m.squad_id
) 
	AS retention_rate_table,

(
    SELECT 
        s_m.squad_id,
        s_m.dwarf_id,
        SUM(
            COALESCE(ds_after.level, 0) - COALESCE(ds_before.level, 0)
        ) AS skill_improvement
    FROM 
        squad_members s_m
    JOIN 
        dwarves d ON s_m.dwarf_id = d.dwarf_id
    JOIN 
        dwarf_skills ds_before ON d.dwarf_id = ds_before.dwarf_id
    JOIN 
        dwarf_skills ds_after ON d.dwarf_id = ds_after.dwarf_id
        AND ds_before.skill_id = ds_after.skill_id
    WHERE 
        ds_before.date < e.departure_date
        AND ds_after.date > e.return_date
    GROUP BY 
        s_m.squad_id, 
		s_m.dwarf_id
) 
	AS skill_improvement_table,


SELECT 
    ms.squad_id,
    ms.name squad_name,
	ms.formation_type,
	dw_leader.name leader_name,
	b_a_t.total_battles,
	w_t.victories,
	
	-- Соотношения побед к общему числу сражений
    COALESCE((ROUND((w_t.victories::DECIMAL / NULLIF(b_a_t.total_battles, 0)) * 100, 2), 0) AS victory_percentage,
	
    COALESCE((ROUND((c_r_t.casualties::DECIMAL / NULLIF(c_r_t.total_members_by_date, 0)) * 100, 2), 0) AS casualty_rate,
	
    COALESCE((ROUND((c_r_t.enemy_casualties::DECIMAL / NULLIF(c_r_t.casualties, 0)), 2), 0) AS casualty_exchange_ratio,
	
	-- Качества экипировки
	a_eq_q_t.avg_equipment_quality,
	
	c_m_t.current_members,
	
	t_m_e_t.total_members_ever,
	
	-- Выживаемость членов отряда в долгосрочной перспективе
	r_r_t.retention_rate,
	
	t_t_s_t.total_training_sessions,
	
	-- История тренировок и их влияния на результаты
	a_t_e_t.avg_training_effectiveness,
	
	-- Истории тренировок и их влияния на результаты
	CORR(victories, total_training_sessions) AS training_battle_correlation,
	
	-- сгруппировали данные по прокачке всех гномов в отряде и вычислили среднее по этой прокачке
	-- Навыков членов отряда и их прогресса
	AVG(s_i_t.skill_improvement) AS avg_combat_skill_improvement,
	
	ROUND(
        victory_percentage * 0.125 +
        casualty_rate * 0.125 +
        casualty_exchange_ratio * 0.125 +
        a_eq_q_t.avg_equipment_quality * 0.125 +
        r_r_t.retention_rate * 0.125 +
        a_t_e_t.avg_training_effectiveness * 0.125 +
        training_battle_correlation * 0.125 +
        avg_combat_skill_improvement * 0.125,
        2
    ) AS overall_effectiveness_score,
	
	-- Related entities for REST API
    JSON_OBJECT(
        'member_ids', (
            SELECT JSON_ARRAYAGG(sm_j.dwarf_id)
            FROM squad_members sm_j
            WHERE sm_j.squad_id = ms.squad_id
        ),
        'product_ids', (
            SELECT JSON_ARRAYAGG(sq_j.equipment_id)
            FROM squad_equipment sq_j
            WHERE sq_j.squad_id = ms.squad_id
        ),
        'battle_report_ids', (
            SELECT JSON_ARRAYAGG(sb_j.report_id)
            FROM squad_battles sb_j
            WHERE sb_j.squad_id = ms.squad_id
        ),
        'training_ids', (
            SELECT JSON_ARRAYAGG(st_j.schedule_id)
            FROM squad_training st_j
            WHERE st_j.squad_id = ms.squad_id
        )
    ) AS related_entities
	
FROM military_squads ms   
JOIN dwarves dw_leader 
				ON dw_leader.dwarf_id = ms.leader_id
JOIN battle_amount_table b_a_t 
				ON b_a_t.squad_id = ms.squad_id
JOIN victories_table w_t 
				ON w_t.squad_id = ms.squad_id
JOIN current_members_table c_m_t 
				ON c_m_t.squad_id = ms.squad_id
JOIN total_members_ever_table t_m_e_t 
				ON t_m_e_t.squad_id = ms.squad_id
JOIN total_training_sessions_table t_t_s_t 
				ON t_t_s_t.squad_id = ms.squad_id
JOIN avg_training_effectiveness_table a_t_e_t 
				ON a_t_e_t.squad_id = ms.squad_id
JOIN casualty_rate_table c_r_t 
				ON c_r_t.squad_id = ms.squad_id
JOIN avg_equipment_quality_table a_eq_q_t 
				ON a_eq_q_t.squad_id = ms.squad_id
JOIN retention_rate_table r_r_t 
				ON r_r_t.squad_id = ms.squad_id
JOIN skill_improvement_table s_i_t 
				ON s_i_t.squad_id = ms.squad_id
GROUP BY     
	ms.squad_id,
    ms.name squad_name,
	ms.formation_type,
	dw_leader.name leader_name,
	b_a_t.total_battles,
	w_t.victories,
	c_r_t.casualties,
	c_r_t.total_members_by_date,
	c_r_t.enemy_casualties, -- верна ли группирока, если в одном случае значение используется в числителе,  в другом в знаменателе? Да, т.к. числ и зн. всегда только один, а не агрегация по значениям.
	a_eq_q_t.avg_equipment_quality
	c_m_t.current_members,
	t_m_e_t.total_members_ever,
	r_r_t.retention_rate,
	t_t_s_t.total_training_sessions,
	a_t_e_t.avg_training_effectiveness,
ORDER BY 
    overall_effectiveness_score DESC;

				

				
				
