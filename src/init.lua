--// Packages
local CollectionService = game:GetService("CollectionService")

local Signal = require(script.Parent.Signal)
local Cache = require(script.Parent.Cache)

local Promise = require(script.Parent.Promise)
type Promise<data...> = Promise.TypedPromise<data...>

local wrapper = require(script.Parent.Wrapper)
type _wrapper<instance> = wrapper._wrapper<instance>
type wrapper<instance> = wrapper.wrapper<instance>

--// Module
local Entity = {}

--// Functions
-- function Entity.trait<entity, addons, params...>(tag: string, init: (entity: entity, self: {}) -> addons)
function Entity.trait<entity, addons, params...>(tag: string, init: (entity: entity, self: _wrapper<entity> & addons, params...) -> ())
    
    type trait = wrapper<entity> & addons
    
    local meta = { __locked = 'locked' }
    local self = setmetatable({}, meta)
    local cache = Cache.async(-1, 'k')
    
    --// Functions
    function self.getAsync(entity: entity,...: params...): Promise<trait>
        
        assert(typeof(entity) == "Instance")
        
        local data = table.pack(...)
        return cache:findFirstPromise(entity) or cache:promise(function(resolve, reject, onCancel)
            
            local traitObject = Instance.new("ObjectValue", entity)
            traitObject.Name = tag
            
            local self = wrapper(traitObject, 'TraitObject')
            ;(init :: any)(entity, self, unpack(data))
            
            entity:AddTag(tag)
            self:cleaner(function() entity:RemoveTag(tag) end)
            
            resolve(self)
        end, entity)
    end
    function self.await(entity: entity): trait
        
        repeat local newEntity = CollectionService:GetInstanceAddedSignal(tag):Wait()
        until newEntity == entity
        
        while true do
            
            local trait = self.find(entity)
            if trait then return trait end
        end
    end
    function self.find(entity: entity): trait?
        
        return cache:find(entity)
    end
    function self.get(entity: entity): trait
        
        return self.getAsync(entity):expect()
    end
    function self.all(): {trait}
        
        return table.clone(cache)
    end
    
    --// Meta
    function meta:__call(entity: entity)
        
        local options = {}
        
        function options:getAsync() return self.getAsync(entity) end
        function options:await() return self.await(entity) end
        function options:find() return self.find(entity) end
        function options:get() return self.get(entity) end
        
        return options
    end
    
    --// End
    Entity.query{ tag=tag }:map(self.get)
    return self
end

type params = { tag: string?, tags: {string}?, root: Instance?, name: string?, class: string? }
function Entity.query(params: params)
    
    local tags, root, name, class = params.tags, params.root, params.name, params.class
    local self = {}
    
    if params.tag then tags = {params.tag, unpack(tags or {})} end
    
    --// Methods
    local entityAdded
    function self:listen(): Signal.Connection
        
        if entityAdded then return entityAdded end
        entityAdded = Signal.new('')
        
        local emitted = Cache.new(-1, 'k')
        local function listenTrigger(trigger)
            
            trigger:Connect(function(entity)
                
                if emitted:find(entity) then return end
                emitted:set(true, entity)
                
                if self:check(entity) then entityAdded:_emit(entity) end
            end)
        end
        if tags then for _,tag in tags do listenTrigger(CollectionService:GetInstanceAddedSignal(tag)) end end
        if root then listenTrigger(root.DescendantAdded) end
        
        return entityAdded
    end
    function self:await(): Instance
        
        return self:listen():await()
    end
    
    function self:iter()
        
        local pool = if tags and tags[1]
            then CollectionService:GetTagged(tags[1])
            else (root or game):GetDescendants()
        
        return coroutine.wrap(function()
            
            for _,entity in pool do
                
                if self:check(entity) then coroutine.yield(entity) end
            end
        end)
    end
    function self:map(mapper: (entity: Instance) -> ()): Signal.Connection
        
        for _,entity in self:all() do task.spawn(mapper, entity) end
        return self:listen():connect(mapper)
    end
    function self:all(): {Instance}
        
        local entities = {}
        local pool = if tags[1]
            then CollectionService:GetTagged(tags[1])
            else (root or game):GetDescendants()
        
        for _,entity in pool do
            
            if self:check(entity) then table.insert(entities, entity) end
        end
        return entities
    end
    function self:find()
        
        return self:iter()()
    end
    
    function self:check(instance: Instance): boolean
        
        if tags then for _,tag in ipairs(tags) do if not instance:HasTag(tag) then return false end end end
        if root and not instance:IsDescendantOf(root) then return false end
        if name and not instance.Name:match(name) then return false end
        if class and not instance:IsA(class) then return false end
        
        return true
    end
    
    --// End
    return table.freeze(self)
end

--// End
return Entity