var/datum/subsystem/events/SSevent

/datum/subsystem/events
	name = "Events"
	priority = 6

	var/list/control = list()	//list of all datum/round_event_control. Used for selecting events based on weight and occurrences.
	var/list/running = list()	//list of all existing /datum/round_event

	var/scheduled = 0			//The next world.time that a naturally occuring random event can be selected.
	var/frequency_lower = 3000	//5 minutes lower bound.
	var/frequency_upper = 9000	//15 minutes upper bound. Basically an event will happen every 5 to 15 minutes.

	var/list/holidays			//List of all holidays occuring today or null if no holidays
	var/wizardmode = 0


/datum/subsystem/events/New()
	NEW_SS_GLOBAL(SSevent)


/datum/subsystem/events/Initialize()
	for(var/type in typesof(/datum/round_event_control))
		var/datum/round_event_control/E = new type()
		if(!E.typepath)
			continue				//don't want this one! leave it for the garbage collector
		if(E.wizardevent && !wizardmode)
			E.weight = 0
		control += E				//add it to the list of all events (controls)
	reschedule()
	getHoliday()
	..()


/datum/subsystem/events/fire()
	checkEvent()
	var/i=1
	for(var/thing in running)
		if(thing)
			thing:process()
			++i
			continue
		running.Cut(i,i+1)


//checks if we should select a random event yet, and reschedules if necessary
/datum/subsystem/events/proc/checkEvent()
	if(scheduled <= world.time)
		spawnEvent()
		reschedule()

//decides which world.time we should select another random event at.
/datum/subsystem/events/proc/reschedule()
	scheduled = world.time + rand(frequency_lower, max(frequency_lower,frequency_upper))
	if(world.time >= 36000 && world.time < 72000) //More than an hour has passed
		if(frequency_lower>2000)
			frequency_lower-=250
		if(frequency_upper>6000)
			frequency_upper-=500
	else if(world.time >= 72000 && world.time < 90000) //Two hours
		if(frequency_lower>2000)
			frequency_lower=2000
		else if(frequency_lower>1000)
			frequency_lower-=250
		if(frequency_upper>6000)
			frequency_upper=6000
		else if(frequency_upper>3000)
			frequency_upper-=500
	else if(world.time >= 90000 && world.time < 108000) //Two and a half hours?!
		if(frequency_lower>1000)
			frequency_lower=1000
		frequency_lower=1000
		if(frequency_upper>3000)
			frequency_upper=3000
		else if(frequency_upper>1500)
			frequency_upper-=500
	else if(world.time > 108000) //Three.
		frequency_lower=1000
		frequency_upper=1500
		//if ((!( ticker ) || emergency_shuttle.location))
		//if(SSshuttle.emergency.mode == SHUTTLE_DOCKED || SSshuttle.emergency.mode == SHUTTLE_CALL)
		//	return
		if(SSshuttle.emergency.mode < SHUTTLE_CALL)
			SSshuttle.emergency.request(null, 1.5)
			log_game("Round time limit reach. Shuttle has been auto-called.")
			message_admins("Three hour mark reached; shuttle auto-called.")
			priority_announce("The shift has ended and the shuttle called.")


		//priority_announce("The emergency shuttle has been called due to the station's abnormal status. It will arrive in [round(emergency_shuttle.timeleft()/60)] minutes.", null, 'sound/AI/shuttlecalled.ogg', "Priority")

//selects a random event based on whether it can occur and it's 'weight'(probability)
/datum/subsystem/events/proc/spawnEvent()
	if(!config.allow_random_events)
//		var/datum/round_event_control/E = locate(/datum/round_event_control/dust) in control
//		if(E)	E.runEvent()
		return

	var/sum_of_weights = 0
	for(var/datum/round_event_control/E in control)
		if(E.occurrences >= E.max_occurrences)	continue
		if(E.earliest_start >= world.time)		continue
		if(E.holidayID)
			if(!holidays || !holidays[E.holidayID])			continue
		if(E.weight < 0)						//for round-start events etc.
			if(E.runEvent() == PROCESS_KILL)
				E.max_occurrences = 0
				continue
			if (E.alertadmins)
				message_admins("Random Event triggering: [E.name] ([E.typepath])")
			log_game("Random Event triggering: [E.name] ([E.typepath])")
			return
		sum_of_weights += E.weight

	sum_of_weights = rand(0,sum_of_weights)	//reusing this variable. It now represents the 'weight' we want to select

	for(var/datum/round_event_control/E in control)
		if(E.occurrences >= E.max_occurrences)	continue
		if(E.earliest_start >= world.time)		continue
		if(E.holidayID)
			if(!holidays || !holidays[E.holidayID])			continue
		sum_of_weights -= E.weight

		if(sum_of_weights <= 0)				//we've hit our goal
			if(E.runEvent() == PROCESS_KILL)//we couldn't run this event for some reason, set its max_occurrences to 0
				E.max_occurrences = 0
				continue
			if (E.alertadmins)
				message_admins("Random Event triggering: [E.name] ([E.typepath])")
			log_game("Random Event triggering: [E.name] ([E.typepath])")
			return


/datum/round_event/proc/findEventArea() //Here's a nice proc to use to find an area for your event to land in!
	var/list/safe_areas = list(
	/area/turret_protected/ai,
	/area/turret_protected/ai_upload,
	/area/engine,
	/area/solar,
	/area/holodeck,
	/area/shuttle
	)

	//These are needed because /area/engine has to be removed from the list, but we still want these areas to get fucked up.
	var/list/danger_areas = list(
	/area/engine/break_room,
	/area/engine/chiefs_office)

	//Need to locate() as it's just a list of paths.
	return locate(pick((the_station_areas - safe_areas) + danger_areas))


//allows a client to trigger an event
//aka Badmin Central
/client/proc/forceEvent()
	set name = "Trigger Event"
	set category = "Fun"

	if(!holder ||!check_rights(R_FUN))
		return

	holder.forceEvent()

/datum/admins/proc/forceEvent()
	var/dat 	= ""
	var/normal 	= ""
	var/magic 	= ""
	var/holiday = ""
	for(var/datum/round_event_control/E in SSevent.control)
		dat = "<BR><A href='?src=\ref[src];forceevent=\ref[E]'>[E]</A>"
		if(E.holidayID)
			holiday	+= dat
		else if(E.wizardevent)
			magic 	+= dat
		else
			normal 	+= dat

	dat = normal + "<BR>" + magic + "<BR>" + holiday

	var/datum/browser/popup = new(usr, "forceevent", "Force Random Event", 300, 750)
	popup.set_content(dat)
	popup.open()


/*
//////////////
// HOLIDAYS //
//////////////
//Uncommenting ALLOW_HOLIDAYS in config.txt will enable holidays

//It's easy to add stuff. Just add a holiday datum in code/modules/holiday/holidays.dm
//You can then check if it's a special day in any code in the game by doing if(SSevent.holidays["Groundhog Day"])

//You can also make holiday random events easily thanks to Pete/Gia's system.
//simply make a random event normally, then assign it a holidayID string which matches the holiday's name.
//Anything with a holidayID, which isn't in the holidays list, will never occur.

//Please, Don't spam stuff up with stupid stuff (key example being april-fools Pooh/ERP/etc),
//And don't forget: CHECK YOUR CODE!!!! We don't want any zero-day bugs which happen only on holidays and never get found/fixed!

//////////////////////////////////////////////////////////////////////////////////////////////////////////
//ALSO, MOST IMPORTANTLY: Don't add stupid stuff! Discuss bonus content with Project-Heads first please!//
//////////////////////////////////////////////////////////////////////////////////////////////////////////
*/

//sets up the holidays and holidays list
/datum/subsystem/events/proc/getHoliday()
	if(!config.allow_holidays)	return		// Holiday stuff was not enabled in the config!

	var/YY = text2num(time2text(world.timeofday, "YY")) 	// get the current year
	var/MM = text2num(time2text(world.timeofday, "MM")) 	// get the current month
	var/DD = text2num(time2text(world.timeofday, "DD")) 	// get the current day

	for(var/H in typesof(/datum/holiday) - /datum/holiday)
		var/datum/holiday/holiday = new H()
		if(holiday.shouldCelebrate(DD, MM, YY))
			holiday.celebrate()
			if(!holidays)
				holidays = list()
			holidays[holiday.name] = holiday

	if(holidays)
		holidays = shuffle(holidays)
		world.update_status()

/datum/subsystem/events/proc/toggleWizardmode()
	wizardmode = !wizardmode
	for(var/datum/round_event_control/E in SSevent.control)
		E.weight = initial(E.weight)
		if((E.wizardevent && !wizardmode) || (!E.wizardevent && wizardmode))
			E.weight = 0
	message_admins("Summon Events has been [wizardmode ? "enabled, events will occur every [SSevent.frequency_lower / 600] to [SSevent.frequency_upper / 600] minutes" : "disabled"]!")
	log_game("Summon Events was [wizardmode ? "enabled" : "disabled"]!")


/datum/subsystem/events/proc/resetFrequency()
	frequency_lower = initial(frequency_lower)
	frequency_upper = initial(frequency_upper)
