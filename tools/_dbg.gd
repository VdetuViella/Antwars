extends SceneTree
func _init():
	var w := SimWorld.new()
	var start := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 4, "day": 20, "hour": 11, "minute": 0, "second": 0}))
	w.new_game(1234, start)
	w.set_time_scale(400.0)
	var t0 := Time.get_ticks_msec()
	var next := 10.0
	while w.bio_day() < 150.0 and Time.get_ticks_msec() - t0 < 240000:
		w.advance(0.1)
		if w.env.feeder_seeds < 2000.0: w.env.feeder_seeds += 2000.0
		if w.env.water_ml < 30.0: w.env.water_ml = 100.0
		if w.bio_day() >= next:
			next += 10.0
			print("día %.0f  %.1f s  obreras %d hormigas %d zonas %d frentes %d dig %d área %.0f necesidad %s debris %d" % [w.bio_day(), (Time.get_ticks_msec() - t0) / 1000.0, w.colony.total_workers(), w.ants.count, w.plan.active_zone_count(), w.dig_front_count, w.ants.task_count[3], w.plan.area_for("brood") + w.plan.area_for("granary"), str(w.space_need()), w.soil.debris.size()])
	quit()
