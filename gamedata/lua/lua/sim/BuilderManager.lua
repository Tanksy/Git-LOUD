--  /lua/sim/BuilderManager.lua
--  Manage builders

local CreateBuilder = import('/lua/sim/Builder.lua').CreateBuilder

local LOUDGETN = table.getn
local LOUDINSERT = table.insert
local LOUDREMOVE = table.remove

local LOUDSORT = table.sort

local ForkThread = ForkThread
local ForkTo = ForkThread

local Random = Random

BuilderManager = Class {

    Create = function(self, brain)
	
        self.Trash = TrashBag()
        self.BuilderData = {}
        self.BuilderCheckInterval = 20
        self.BuilderList = false
        self.Active = false
        self.NumBuilders = 0
		
    end,
    
    Destroy = function(self)
	
        for _,bType in self.BuilderData do
		
			for k,v in bType do
			
                v = nil
				
            end
			
        end
		
        self.Trash:Destroy()
		
    end,
    
    ForkThread = function(self, fn, ...)
	
        local thread = ForkThread(fn, self, unpack(arg))
        
		self.Trash:Add(thread)
		
    end,

    SetEnabled = function(self, brain, enable)

        if enable then

			self.Active = true		
			self:ForkThread( self.ManagerThread, brain)

        elseif not enable then

			self.Active = false		
			self.Trash:Destroy()

        end

	end,

    SortBuilderList = function(self, bType)

		if self.BuilderData[bType] then

			local oldtable = table.copy(self.BuilderData[bType].Builders)

			LOUDSORT(oldtable, function(a,b) return a.Priority > b.Priority end )

			self.BuilderData[bType].Builders = table.copy(oldtable)

			self.BuilderData[bType].NeedSort = false

		end

    end,

    AddBuilder = function(self, brain, builderData, locationType, builderType)

        local newBuilder = CreateBuilder(brain, builderData, locationType, builderType)

        self:AddInstancedBuilder(newBuilder, builderType, brain)
		
    end,
    
    AddInstancedBuilder = function(self, newBuilder, builderType, aiBrain)

        local BuilderType = builderType	or 'Any'
        
        -- not all bases support all builder types -- ie. FBM at naval base only supports Sea
        -- and likewise land bases don't support Sea -- this is particular mostly to the 
        -- FactoryBuilderManager - so look there for more information
        if self.BuilderData[BuilderType] then

            if newBuilder then
    
                LOUDINSERT( self.BuilderData[BuilderType].Builders, newBuilder )

                self.BuilderData[BuilderType].NeedSort = true
                self.BuilderList = true

                self.NumBuilders = self.NumBuilders + 1
			
            end

            if newBuilder.InstantCheck then
		
                self:ManagerLoopBody(newBuilder)
			
            end
        
        end
		
    end,
    
    GetBuilderPriority = function(self, builderName)

        for _,bType in self.BuilderData do

            for _,builder in bType.Builders do

                if builder.BuilderName == builderName then
				
                    return builder.Priority
					
                end

            end
			
        end

        return false
		
    end,
    
    SetBuilderPriority = function( manager, builderName, priority, temporary )
	
        for k1,bType in manager.BuilderData do
		
            for k2,builder in bType.Builders do
			
                if builder.BuilderName == builderName then

					if builder.Priority != priority then
					
						builder:SetPriority(priority, temporary)

						if priority == 0 and not temporary then
							
							table.remove( manager.BuilderData[k1].Builders, k2 )
							
						end
					
						manager.BuilderData[k1].NeedSort = true
						
					end
					
					return builder
					
                end
				
            end
			
        end
		
		return false
		
    end,

    AssignTimeout = function( self, builderName, timeoutticks )
	
		--LOG("*AI DEBUG Assigning timeout to "..repr(builderName))
    
		WaitTicks(2)	-- this allows platoon to disband first (which would possibly reset the builder to normal priority)

        local builder = self:SetBuilderPriority( builderName, 10, true ) -- set the builder to priority 10 temporarily

		local priority = self:GetBuilderPriority(builderName) -- retrieve that priority to make sure that it actually took since it's possible the builder may no longer exist
		
		if builder and priority then

			if timeoutticks then
				WaitTicks(timeoutticks)
			end

			builder:ResetPriority(self)

		end

    end,
	
    AddBuilderType = function(self, buildertype)
	
        self.BuilderData[buildertype] = { Builders = {}, NeedSort = true }
		
    end,
	

	-- loop thru all possible tasks for this type of builder (Engineer, Platoon or Factory) in priority sequence (high to low) at this location (self)
	-- The tasks are sorted from highest priority to lowest (except those which are set to zero at some point)
	-- ignore any job with a priority of 0
	-- the priority trigger is set by the first job that passes all checks and only jobs of the same priority will be considered after that
	-- jobs that pass all checks are added to the temporary table of possible jobs 
	-- stop looping once you encounter a job with a lower priority than that trigger (but not zero - those are ignored)
	-- and randomly return one of the possible jobs
    GetHighestBuilder = function( self, unit, aiBrain )

		-- function that checks all the conditions of a builder
		-- only returns true if all conditions pass 
		local GetBuilderStatus = function( task )
			
			--LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.LocationType.." "..self.ManagerType.." "..unit.BuilderType.." testing Builder "..task.BuilderName.." at "..task.Priority)
		
			for _,value in task.BuilderConditions do
			
				--if unit.BuilderType == 'Commander' then
					--LOG("*AI DEBUG "..aiBrain.Nickname.."         checking condition "..repr(value).." "..repr(aiBrain.ConditionsMonitor.ResultTable[value].FunctionName) )
				--end

				if not aiBrain.ConditionsMonitor.ResultTable[value].Instant then
				
					if not aiBrain.ConditionsMonitor.ResultTable[value].Status then
					
						return false
					end
				else
					if not aiBrain.ConditionsMonitor.ResultTable[value]:GetStatus(aiBrain) then
					
						return false
					end
				end
			end
			
			return true
		end

		-- sort the builders list if needed
		if self.BuilderData[unit.BuilderType].NeedSort then
        
            if ScenarioInfo.PriorityDialog then
                LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.ManagerType.." sorting "..unit.BuilderType.." tasks")
            end

			LOUDSORT( self.BuilderData[unit.BuilderType].Builders, function(a,b) return a.Priority > b.Priority end )
            
            if ScenarioInfo.PriorityDialog then
                if not self.BuilderData[unit.BuilderType].displayed then
                
                    LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.ManagerType.." "..self.LocationType.." SORTED "..unit.BuilderType.." Builders are ")
                    
                    for k,v in self.BuilderData[unit.BuilderType].Builders do
                    
                        LOG("*AI DEBUG "..aiBrain.Nickname.." "..v.Location.." "..v.Priority.." "..v.BuilderName)
                    end
                    
                    self.BuilderData[unit.BuilderType].displayed = true
                end
            end
			
			self.BuilderData[unit.BuilderType].NeedSort = false
        end
		
		-- use the BuilderParamCheck function specific to the Manager that called this function (ie. Engineer or Factory)
        local BuilderParamCheck = self.BuilderParamCheck		
		
        local found = false
        local possibleBuilders = {}
		local counter = 0
		
		local TaskList = self.BuilderData[unit.BuilderType].Builders or {}

		local continuesearching = true

        for k,task in TaskList do
		
			if task.Priority > 100 and (task.InstancesAvailable > 0 or self.ManagerType == 'FBM') and continuesearching then
			
				-- if no task found yet or priority is the same as one we have already added - examine the task
                if (not found) or task.Priority >= found then

                    if GetBuilderStatus( task ) then

                        if BuilderParamCheck(self, task, unit) then
						
                            found = task.Priority
                            possibleBuilders[counter+1] = k
							counter = counter + 1
                        end
                    end
                    
                elseif found and task.Priority < found then
				
					continuesearching = false
                end
            else

				if task.OldPriority and task.OldPriority == 0 then

					if ScenarioInfo.PriorityDialog then
						LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.ManagerType.." "..self.LocationType.." Removing "..repr(self.BuilderData[unit.BuilderType].Builders[k].BuilderName) )
					end
					
					LOUDREMOVE(self.BuilderData[unit.BuilderType].Builders,k)

					self.BuilderData[unit.BuilderType].NeedSort = true
				end
			end
			
			if Builders[TaskList[k].BuilderName].PriorityFunction then

				local newPri = false
				local temporary = true
				
				newPri,temporary = Builders[TaskList[k].BuilderName]:PriorityFunction( aiBrain, unit )

				-- if the priority function reports a different priority than current priority
				if newPri and newPri != task.Priority and (task.InstancesAvailable > 0 or self.ManagerType == 'FBM') then
				
					if ScenarioInfo.PriorityDialog then
						LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.ManagerType.." "..self.LocationType.." PriorityFunction for "..repr(self.BuilderData[unit.BuilderType].Builders[k].BuilderName).." changes to "..newPri.." from "..task.Priority )
					end

					self.BuilderData[unit.BuilderType].Builders[k]:SetPriority( newPri, temporary )
					
					self.BuilderData[unit.BuilderType].NeedSort = true
				end
			end
        end

        if counter > 0 then 
			return TaskList[ possibleBuilders[ Random(1, counter) ] ]
        end
		
		if self.ManagerType == 'FBM' then
			unit.failedbuilds = unit.failedbuilds + 1
		end
		
        return false
    end,
	
	RebuildTable = function(self,oldtable)
	
		local temptable = {}
		local LOUDINSERT = table.insert
		local type = type
		
		for k,v in oldtable do
		
			if v != nil then
			
				if type(k) == 'string' then
				
					temptable[k] = v
				else
					LOUDINSERT(temptable, v)
				end
			end
		end
		
		return temptable
	end,
    
    ManagerLoopBody = function(self,builder,bType)
	
        if builder:CalculatePriority(self) then
		
            self.BuilderData[bType].NeedSort = true
        end
    end,
  
	-- originally this thread ran for each manager - but now just the PFM
	-- checks if the PFM builderlist needs to be resorted due to a priority change
	
	-- This thread is the core of the PFM -- cycles thru all the platoons as long as the manager is Active
	
	-- The loop time is controlled by the duration of the BrainConditionMonitor duration and if the base
	-- is the PrimaryLandAttackBase or not
	
	-- essentially, as more conditions must be checked (more bases) we slow the rate of platoon checking
	-- run all bases at 2/3 the rate of the Condition Monitor -- except primary runs at 1 to 1
    
    -- One huge difference in the PFM is that unlike the EM and the FM - if two tasks have equal priority
    -- and they both pass their status checks, the PFM will form them in alphabetical order
    ManagerThread = function(self, brain)

        local LOUDCEIL = math.ceil
		local LOUDFLOOR = math.floor
        local WaitTicks = coroutine.yield
       
        local ManagerLoopBody = self.ManagerLoopBody

		local duration = (self.BuilderCheckInterval) * 10
        local ticksize = 1	

		local tasks = self.NumBuilders
		
		local GetBuilderStatus = function( self, ResultTable )
			
			for _,v in self.BuilderConditions do
			
				if not ResultTable[v].Instant then
				
					if not ResultTable[v].Status then
					
						return false
						
					end
					
				else
				
					if not ResultTable[v]:GetStatus(brain) then
					
						return false
						
					end
					
				end
				
			end
		
			return true
		end		
		
		local numTicks, numTested, numPassed
		
		local PoolGreaterAtLocation = import ('/lua/editor/UnitCountBuildConditions.lua').PoolGreaterAtLocation
		
        while self.Active do
		
			if self.BuilderData['Any'].NeedSort then
            
                local ResetPFMTasks = import('/lua/loudutilities.lua').ResetPFMTasks
            
				-- reset the tasks with Priority Functions at this PFM
				ResetPFMTasks( self, brain )
			
				LOUDSORT( self.BuilderData['Any'].Builders, function(a,b) return a.Priority > b.Priority end )
				
                --LOG("*AI DEBUG "..brain.Nickname.." SORTED "..repr(self.ManagerType).." tasks at "..repr(self.LocationType).." is "..repr(self.BuilderData['Any'].Builders))
                
				self.BuilderData['Any'].NeedSort = false
				
			end

			-- The PFM is the only manager truly affected by this since factories and engineers seek their own jobs
			-- Simply, the PFM at a Primary Base runs twice as fast as the Conditions Monitor while other bases run
			-- at the same frequency as the Conditions Monitor thread
			if brain.BuilderManagers[self.LocationType].PrimaryLandAttackBase or brain.BuilderManagers[self.LocationType].PrimarySeaAttackBase then
			
				self.BuilderCheckInterval = brain.ConditionsMonitor.ThreadWaitDuration * .5
				
			else
			
				self.BuilderCheckInterval = brain.ConditionsMonitor.ThreadWaitDuration
				
			end		
			
			if tasks != self.NumBuilders or ((self.BuilderCheckInterval * 10) != duration) then
			
				duration = self.BuilderCheckInterval * 10
				tasks = self.NumBuilders
				ticksize = LOUDFLOOR( duration / tasks )
				
			end

            numTicks = 0
			numTested = 0
			numPassed = 0
			
            -- there must be units in the Pool or there will be nothing to form
			if PoolGreaterAtLocation( brain, self.LocationType, 0, categories.ALLUNITS - categories.ENGINEER ) then
			
                -- loop thru all the platoon builders
				for bType,bTypeData in self.BuilderData do
                
                    if ScenarioInfo.PlatoonDialog then
                        LOG("*AI DEBUG "..brain.Nickname.." PFM "..(self.LocationType).." Begins Processing "..repr(bType).." at "..repr(GetGameTimeSeconds()) )
                    end
			
					for _,bData in bTypeData.Builders do
					
						if bData.Priority >= 100 then
--[[                        
                            if ScenarioInfo.PlatoonDialog then
                        
                                LOG("*AI DEBUG "..brain.Nickname.." PFM "..(self.LocationType).." testing "..repr(bData.Priority).." "..repr(bData.BuilderName))
                                
                            end
--]]					
							numTested = numTested + 1
						
							if GetBuilderStatus( bData, brain.ConditionsMonitor.ResultTable ) then
                            
                                if ScenarioInfo.PlatoonDialog then
                                    LOG("*AI DEBUG "..brain.Nickname.." PFM "..self.LocationType.." trys to form "..repr(bData.BuilderName))
                                end
						
								ForkTo ( ManagerLoopBody, self, bData, bType, brain )
							
								numPassed = numPassed + 1
						
								WaitTicks(ticksize)
								numTicks = numTicks + ticksize
							
							end
						end
					end
				end
			end
			
			if numTicks < duration then
			
				WaitTicks( duration - numTicks )
				
			end
			
        end
		
    end,
	
}

--[[
    ClearBuilderLists = function(self)
        for k,v in self.Builders do
            v.Builders = {}
            v.NeedSort = false
        end
        self.BuilderList = false
    end,
	
	-- while this function will still return a result, it has no way of knowing if the builder
	-- exists under multiple builder types (ie. - T1,T2,T3 engineers being the best example)
	-- it will simply return the first one it encounters with the correct name -- nope - 
	-- can't really use this anymore 
    GetBuilder = function(self, builderName)
	
        for _,bType in self.BuilderData do
		
            for _,builder in bType.Builders do
			
                if builder.BuilderName == builderName then
				
                    return builder
					
                end
				
            end
			
        end
		
        return false
		
    end,
	
--]]