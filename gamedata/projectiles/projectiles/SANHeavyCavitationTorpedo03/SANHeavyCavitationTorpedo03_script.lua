local SHeavyCavitationTorpedo = import('/lua/seraphimprojectiles.lua').SHeavyCavitationTorpedo
local RandomFloat = import('/lua/utilities.lua').GetRandomFloat
local EffectTemplate = import('/lua/EffectTemplates.lua')

local ForkThread = ForkThread
local WaitSeconds = WaitSeconds

local VDist2 = VDist2

local CreateEmitterOnEntity = CreateEmitterOnEntity

-- this torpedo is the split projectile created by the Heavy Cavitation Torpedo 1 ( from T2 Torpedo launcher )
SANHeavyCavitationTorpedo03 = Class(SHeavyCavitationTorpedo) {

    OnCreate = function(self)
	
        SHeavyCavitationTorpedo.OnCreate( self )
		
        self:ForkThread( self.PauseUntilTrack )
		
        CreateEmitterOnEntity( self, self:GetArmy(), EffectTemplate.SHeavyCavitationTorpedoFxTrails )
		
    end,

    PauseUntilTrack = function(self)
	
        local distance = self:GetDistanceToTarget()
		
        local waittime
		
        -- The pause time needs to scale down depending on how far away the target is, otherwise
        -- the torpedoes will initially shoot past their target.
        if distance > 6 then
		
            waittime = .45
			
            if distance > 12 then
			
                waittime = .7
				
                if distance > 18 then
				
                    waittime = 1
					
                end
				
            end
			
        else
		
            waittime = .2
		
			self:SetTurnRate(720)

        end
		
        WaitSeconds(waittime)
		
        self:TrackTarget(true)

    end,

    GetDistanceToTarget = function(self)
	
        local tpos = self:GetCurrentTargetPosition()
		
        local mpos = self:GetPosition()
		
        local dist = VDist2(mpos[1], mpos[3], tpos[1], tpos[3])
		
        return dist
		
    end,
}

TypeClass = SANHeavyCavitationTorpedo03