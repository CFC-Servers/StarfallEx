
--- Library for creating and manipulating physics-less models AKA "Holograms".
-- @shared
local holograms_library = SF.RegisterLibrary("holograms")

--- Hologram type
local hologram_methods, hologram_metamethods = SF.RegisterType("Hologram")

local checktype = SF.CheckType
local checkluatype = SF.CheckLuaType
local checkpermission = SF.Permissions.check


SF.Holograms = {}

SF.Permissions.registerPrivilege("hologram.modify", "Modify holograms", "Allows the user to modify holograms", { entities = {} })

SF.Holograms.Methods = hologram_methods
SF.Holograms.Metatable = hologram_metamethods

local ang_meta, vec_meta, ent_meta
local wrap, unwrap, vunwrap, aunwrap, ewrap, eunwrap
SF.AddHook("postload", function()
	ang_meta = SF.Angles.Metatable
	vec_meta = SF.Vectors.Metatable
	ent_meta = SF.Entities.Metatable

	vunwrap = SF.Vectors.Unwrap
	aunwrap = SF.Angles.Unwrap
	ewrap = SF.Entities.Wrap
	eunwrap = SF.Entities.Unwrap

	SF.ApplyTypeDependencies(hologram_methods, hologram_metamethods, ent_meta)
	wrap, unwrap = SF.CreateWrapper(hologram_metamethods, true, false, nil, ent_meta)

	SF.Holograms.Wrap = wrap
	SF.Holograms.Unwrap = unwrap
	
	--- Casts a hologram entity into the hologram type
	-- @name Entity.getHologram
	-- @class function
	-- @return Hologram type
	function SF.Entities.Methods:getHologram()
		checktype(self, ent_meta)
	end
end)

if SERVER then

	SF.Holograms.personalquota = CreateConVar("sf_holograms_personalquota", "100", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
		"The number of holograms allowed to spawn via Starfall scripts for a single player")

	SF.Permissions.registerPrivilege("hologram.create", "Create hologram", "Allows the user to create holograms")

	-- Table with player keys that automatically cleans when player leaves.
	local plyCount = SF.EntityTable("playerHolos")

	SF.AddHook("initialize", function(inst)
		inst.data.holograms = {
			holos = {},
			count = 0
		}
		plyCount[inst.player] = plyCount[inst.player] or 0
	end)

	local function hologramOnDestroy(holoent, holodata, ply)
		holodata[holoent] = nil
		if plyCount[ply] then
			plyCount[ply] = plyCount[ply] - 1
		end
	end

	SF.AddHook("deinitialize", function(inst)
		local holos = inst.data.holograms.holos
		local holo = next(holos)
		while holo do
			if IsValid(holo) then
				holo:RemoveCallOnRemove("starfall_hologram_delete")
				hologramOnDestroy(holo, holos, inst.player)
				holo:Remove()
			end
			holo = next(holos, holo)
		end
	end)
	
	--- Creates a hologram.
	-- @server
	-- @return The hologram object
	function holograms_library.create (pos, ang, model, scale)
		local instance = SF.instance
		checkpermission(instance,  nil, "hologram.create")
		checktype(pos, vec_meta)
		checktype(ang, ang_meta)
		checkluatype(model, TYPE_STRING)
		if scale ~= nil then
			checktype(scale, vec_meta)
			scale = vunwrap(scale)
		end

		local pos = vunwrap(pos)
		local ang = aunwrap(ang)

		local holodata = instance.data.holograms.holos

		if plyCount[instance.player] >= SF.Holograms.personalquota:GetInt() then
			SF.Throw("Can't spawn holograms, maximum personal limit of " .. SF.Holograms.personalquota:GetInt() .. " has been reached", 2)
		end

		local holoent = ents.Create("starfall_hologram")
		if holoent and holoent:IsValid() then
			holoent:SetPos(SF.clampPos(pos))
			holoent:SetAngles(ang)
			holoent:SetModel(model)
			holoent:CallOnRemove("starfall_hologram_delete", hologramOnDestroy, holodata, instance.player)
			holoent:Spawn()

			hook.Run("PlayerSpawnedSENT", instance.player, holoent)

			if scale then
				holoent:SetScale(scale)
			end

			holodata[holoent] = true
			plyCount[instance.player] = plyCount[instance.player] + 1

			return wrap(holoent)
		end
	end

	--- Checks if a user can spawn anymore holograms.
	-- @server
	-- @return True if user can spawn holograms, False if not.
	function holograms_library.canSpawn()
		if not SF.Permissions.hasAccess(SF.instance,  nil, "hologram.create") then return false end
		return plyCount[SF.instance.player] < SF.Holograms.personalquota:GetInt()
	end

	--- Checks how many holograms can be spawned
	-- @server
	-- @return number of holograms able to be spawned
	function holograms_library.hologramsLeft ()
		if not SF.Permissions.hasAccess(SF.instance,  nil, "hologram.create") then return 0 end
		return SF.Holograms.personalquota:GetInt() - plyCount[SF.instance.player]
	end

	--- Sets the hologram linear velocity
	-- @param vel New velocity
	-- @server
	function hologram_methods:setVel (vel)
		checktype(self, hologram_metamethods)
		checktype(vel, vec_meta)
		local vel = vunwrap(vel)
		local holo = unwrap(self)
		if holo then holo:SetLocalVelocity(vel) end
	end

	--- Sets the hologram's angular velocity.
	-- @param angvel *Vector* angular velocity.
	-- @server
	function hologram_methods:setAngVel (angvel)
		checktype(self, hologram_metamethods)
		checktype(angvel, ang_meta)
		local holo = unwrap(self)
		if holo then holo:SetLocalAngularVelocity(aunwrap(angvel)) end
	end
else
	--- Sets a hologram entity's model to a custom Mesh
	-- @client
	-- @param mesh The mesh to set it to or nil to set back to normal
	function hologram_methods:setMesh(mesh)
		local instance = SF.instance
		checkpermission(instance, nil, "mesh")
		local ent = eunwrap(self)
		if not isValid(ent) or ent:GetClass()~="starfall_hologram" then SF.Throw("The entity is invalid or not a hologram", 2) end
		checkpermission(instance, ent, "entities.setRenderProperty")
		if mesh then
			checktype(mesh, SF.Mesh.Metatable)
			ent.custom_mesh = SF.Mesh.Unwrap(mesh)
			ent.custom_mesh_data = instance.data.meshes
		else
			ent.custom_mesh = nil
		end
	end

	--- Sets a hologram entity's material to a custom starfall material
	-- @client
	-- @param material The material to set it to or nil to set back to default
	function hologram_methods:setMaterial(material)
		local instance = SF.instance
		local ent = eunwrap(self)
		if not isValid(ent) or ent:GetClass()~="starfall_hologram" then SF.Throw("The entity is invalid or not a hologram", 2) end
		checkpermission(instance, ent, "entities.setRenderProperty")
		if material then
			checktype(material, SF.Materials.Metatable)
			ent.Material = SF.Materials.Unwrap(material)
		else
			ent.Material = ent.DefaultMaterial
		end
	end

	--- Sets a hologram entity's renderbounds
	-- @client
	-- @param mins The lower bounding corner coordinate local to the hologram
	-- @param maxs The upper bounding corner coordinate local to the hologram
	function hologram_methods:setRenderBounds(mins, maxs)
		checktype(mins, vec_meta)
		checktype(maxs, vec_meta)
		local ent = eunwrap(self)
		if not isValid(ent) or ent:GetClass()~="starfall_hologram" then SF.Throw("The entity is invalid or not a hologram", 2) end
		checkpermission(SF.instance, ent, "entities.setRenderProperty")
		ent:SetRenderBounds(vunwrap(mins), vunwrap(maxs))
	end

	--- Sets a hologram entity's rendermatrix
	-- @client
	-- @param mat Starfall matrix to use
	function hologram_methods:setRenderMatrix(mat)
		if mat ~= nil then checktype(mat, SF.VMatrix.Metatable) end
		local ent = eunwrap(self)
		if not isValid(ent) or ent:GetClass()~="starfall_hologram" then SF.Throw("The entity is invalid or not a hologram", 2) end
		checkpermission(SF.instance, ent, "entities.setRenderProperty")
		
		if mat then
			local matrix = SF.VMatrix.Unwrap(mat)
			if matrix:IsIdentity() then
				ent:DisableMatrix("RenderMultiply")
			else
				ent:EnableMatrix("RenderMultiply", matrix)
			end
		else
			ent:DisableMatrix("RenderMultiply")
		end
	end
end

--- Sets the hologram scale
-- @param scale Vector new scale
-- @shared
function hologram_methods:setScale (scale)
	checktype(self, hologram_metamethods)
	checktype(scale, vec_meta)
	local scale = vunwrap(scale)
	local holo = unwrap(self)
	if holo then
		holo:SetScale(scale)
	end
end

--- Updates a clip plane
-- @shared
function hologram_methods:setClip (index, enabled, origin, normal, islocal)
	checktype(self, hologram_metamethods)
	checkluatype(index, TYPE_NUMBER)
	checkluatype(enabled, TYPE_BOOL)
	checktype(origin, vec_meta)
	checktype(normal, vec_meta)
	checkluatype(islocal, TYPE_BOOL)

	local origin, normal = vunwrap(origin), vunwrap(normal)

	local holo = unwrap(self)
	if holo then
		if enabled and not holo.clips[index] and table.Count(holo.clips)==8 then
			SF.Throw("The maximum hologram clips is 8", 2)
		end
		holo:UpdateClip(index, enabled, origin, normal, islocal)
	end
end

--- Returns a table of flexname -> flexid pairs for use in flex functions.
-- These IDs become invalid when the hologram's model changes.
-- @shared
function hologram_methods:getFlexes()
	checktype(self, hologram_metamethods)
	local holoent = unwrap(self)
	local flexes = {}
	for i = 0, holoent:GetFlexNum()-1 do
		flexes[holoent:GetFlexName(i)] = i
	end
	return flexes
end

--- Sets the weight (value) of a flex.
-- @shared
function hologram_methods:setFlexWeight(flexid, weight)
	checktype(self, hologram_metamethods)
	checkluatype(flexid, TYPE_NUMBER)
	checkluatype(weight, TYPE_NUMBER)
	flexid = math.floor(flexid)
	local holoent = unwrap(self)
	if flexid < 0 or flexid >= holoent:GetFlexNum() then
		SF.Throw("Invalid flex: "..flexid, 2)
	end
	if IsValid(holoent) then
		holoent:SetFlexWeight(flexid, weight)
	end
end

--- Sets the scale of all flexes of a hologram
function hologram_methods:setFlexScale(scale)
	checktype(self, hologram_metamethods)
	checkluatype(scale, TYPE_NUMBER)
	local holoent = unwrap(self)
	if IsValid(holoent) then
		holoent:SetFlexScale(scale)
	end
end

--- Sets the model of a hologram
-- @shared
-- @class function
-- @param model string model path
function hologram_methods:setModel (model)
	checkluatype(model, TYPE_STRING)
	if not util.IsValidModel(model) then SF.Throw("Model is invalid", 2) end

	local this = unwrap(self)
	if IsValid(this) then
		this:SetModel(model)
	end
end

--- Suppress Engine Lighting of a hologram. Disabled by default.
-- @shared
-- @class function
-- @param suppress Boolean to represent if shading should be set or not.
function hologram_methods:suppressEngineLighting (suppress)
	checkluatype(suppress, TYPE_BOOL)

	local this = unwrap(self)
	if IsValid(this) then
		this:SetSuppressEngineLighting(suppress)
	end
end

--- Animates a hologram
-- @shared
-- @class function
-- @param animation number or string name
-- @param frame The starting frame number
-- @param rate Frame speed. (1 is normal)
function hologram_methods:setAnimation(animation, frame, rate)
	local Holo = unwrap(self)
	if not IsValid(Holo) then return end

	if isstring(animation) then
		animation = Holo:LookupSequence(animation)
	end

	frame = frame or 0
	rate = rate or 1

	if not Holo.Animated then
		-- This must be run once on entities that will be animated
		Holo.Animated = true
		Holo.AutomaticFrameAdvance = true

		local OldThink = Holo.Think
		function Holo:Think()
			OldThink(self)
			self:NextThink(CurTime())
			return true
		end
	end
	Holo:ResetSequence(animation)
	Holo:SetCycle(frame)
	Holo:SetPlaybackRate(rate)
end

--- Get the length of the current animation
-- @shared
-- @class function
-- @return Length of current animation in seconds
function hologram_methods:getAnimationLength()
	local Holo = unwrap(self)
	if not IsValid(Holo) then return -1 end

	return Holo:SequenceDuration()
end

--- Convert animation name into animation number
-- @shared
-- @param animation Name of the animation
-- @return Animation index
function hologram_methods:getAnimationNumber(animation)
	local Holo = unwrap(self)
	if not IsValid(Holo) then return 0 end

	return Holo:LookupSequence(animation) or 0
end

--- Set the pose value of an animation. Turret/Head angles for example.
-- @shared
-- @class function
-- @param pose Name of the pose parameter
-- @param value Value to set it to.
function hologram_methods:setPose(pose, value)
	local Holo = unwrap(self)
	if not IsValid(Holo) then return end

	Holo:SetPoseParameter(pose, value)
end

--- Get the pose value of an animation
-- @shared
-- @class function
-- @param pose Pose parameter name
-- @return Value of the pose parameter
function hologram_methods:getPose(pose)
	local Holo = unwrap(self)
	if not IsValid(Holo) then return end

	return Holo:GetPoseParameter(pose)
end
