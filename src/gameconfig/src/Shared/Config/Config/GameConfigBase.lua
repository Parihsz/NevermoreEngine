--[=[
	@class GameConfigBase
]=]

local require = require(script.Parent.loader).load(script)

local BaseObject = require("BaseObject")
local RxAttributeUtils = require("RxAttributeUtils")
local AttributeUtils = require("AttributeUtils")
local GameConfigConstants = require("GameConfigConstants")
local RxInstanceUtils = require("RxInstanceUtils")
local GameConfigUtils = require("GameConfigUtils")
local RxBinderUtils = require("RxBinderUtils")
local GameConfigAssetTypes = require("GameConfigAssetTypes")
local RxBrioUtils = require("RxBrioUtils")
local Rx = require("Rx")
local ObservableMapSet = require("ObservableMapSet")
local GameConfigAssetTypeUtils = require("GameConfigAssetTypeUtils")

local GameConfigBase = setmetatable({}, BaseObject)
GameConfigBase.ClassName = "GameConfigBase"
GameConfigBase.__index = GameConfigBase

--[=[
	Constructs a new game config.
	@param folder
	@return GameConfigBase
]=]
function GameConfigBase.new(folder: Instance)
	local self = setmetatable(BaseObject.new(folder), GameConfigBase)

	AttributeUtils.initAttribute(self._obj, GameConfigConstants.GAME_ID_ATTRIBUTE, game.GameId)

	-- Setup observable indexes
	self._assetTypeToAssetConfig = ObservableMapSet.new()
	self._maid:GiveTask(self._assetTypeToAssetConfig)

	self._assetKeyToAssetConfig = ObservableMapSet.new()
	self._maid:GiveTask(self._assetKeyToAssetConfig)

	self._assetIdToAssetConfig = ObservableMapSet.new()
	self._maid:GiveTask(self._assetIdToAssetConfig)

	self._assetTypeToAssetKeyMappings = {}
	self._assetTypeToAssetIdMappings = {}

	-- Setup assetType mappings to key mapping observations
	for _, assetType in pairs(GameConfigAssetTypes) do
		self._assetTypeToAssetKeyMappings[assetType] = ObservableMapSet.new()
		self._maid:GiveTask(self._assetTypeToAssetKeyMappings[assetType])

		self._assetTypeToAssetIdMappings[assetType] = ObservableMapSet.new()
		self._maid:GiveTask(self._assetTypeToAssetIdMappings[assetType])

		self._maid:GiveTask(self._assetTypeToAssetConfig:ObserveItemsForKeyBrio(assetType)
			:Subscribe(function(brio)
				if brio:IsDead() then
					return
				end

				local gameAssetConfig = brio:GetValue()
				local maid = brio:ToMaid()

				maid:GiveTask(self._assetTypeToAssetKeyMappings[assetType]:Add(gameAssetConfig, gameAssetConfig:ObserveAssetKey()))
				maid:GiveTask(self._assetTypeToAssetIdMappings[assetType]:Add(gameAssetConfig, gameAssetConfig:ObserveAssetId()))
			end))
	end

	return self
end

--[=[
	Gets the current folder
	@return Instance
]=]
function GameConfigBase:GetFolder()
	return self._obj
end

--[=[
	Returns an array of all the assets of that type underneath this config
	@return { GameConfigAssetBase }
]=]
function GameConfigBase:GetAssetsOfType(assetType: string)
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")

	return self._assetTypeToAssetConfig:GetListForKey(assetType)
end

--[=[
	Returns an array of all the assets of that type underneath this config
	@param assetType
	@param assetKey
	@return { GameConfigAssetBase }
]=]
function GameConfigBase:GetAssetsOfTypeAndKey(assetType: string, assetKey: string)
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetKey) == "string", "Bad assetKey")

	return self._assetTypeToAssetKeyMappings[assetType]:GetListForKey(assetKey)
end

--[=[
	Returns an array of all the assets of that type underneath this config
	@param assetType
	@param assetId
	@return { GameConfigAssetBase }
]=]
function GameConfigBase:GetAssetsOfTypeAndId(assetType: string, assetId: number)
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetId) == "number", "Bad assetId")

	return self._assetTypeToAssetIdMappings[assetType]:GetListForKey(assetId)
end

--[=[
	Returns an observable matching these types and the key
	@param assetType
	@param assetKey
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase:ObserveAssetByTypeAndKeyBrio(assetType: string, assetKey: string)
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetKey) == "string", "Bad assetKey")

	return self._assetTypeToAssetKeyMappings[assetType]:ObserveItemsForKeyBrio(assetKey)
end

--[=[
	Returns an observable matching these types and the id
	@param assetType
	@param assetId
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase:ObserveAssetByTypeAndIdBrio(assetType: string, assetId: number)
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetId) == "number", "Bad assetId")

	return self._assetTypeToAssetIdMappings[assetType]:ObserveItemsForKeyBrio(assetId)
end

--[=[
	Observes all matching assets of this id
	@param assetId
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase:ObserveAssetByIdBrio(assetId: number)
	assert(type(assetId) == "number", "Bad assetId")

	return self._assetIdToAssetConfig:ObserveItemsForKeyBrio(assetId)
end

--[=[
	Observes all matching assets of this key
	@param assetKey
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase:ObserveAssetByKeyBrio(assetKey: string)
	assert(type(assetKey) == "string", "Bad assetKey")

	return self._assetKeyToAssetConfig:ObserveItemsForKeyBrio(assetKey)
end

--[=[
	Observes all matching assets of this type
	@param assetType
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase:ObserveAssetByTypeBrio(assetType: string)
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")

	return self._assetTypeToAssetConfig:ObserveItemsForKeyBrio(assetType)
end

--[=[
	Initializes the observation. Should be called by the class inheriting this object.
]=]
function GameConfigBase:InitObservation()
	if self._setupObservation then
		return
	end

	self._setupObservation = true

	local observables = {}
	for _, assetType in pairs(GameConfigAssetTypes) do
		table.insert(observables, self:_observeAssetFolderBrio(assetType):Pipe({
			RxBrioUtils.switchMapBrio(function(folder)
				return RxBinderUtils.observeBoundChildClassBrio(self:GetGameConfigAssetBinder(), folder)
			end);
		}))
	end

	-- hook up mapping
	self._maid:GiveTask(Rx.merge(observables):Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		local gameAssetConfig = brio:GetValue()
		local maid = brio:ToMaid()

		maid:GiveTask(self._assetTypeToAssetConfig:Add(gameAssetConfig, gameAssetConfig:ObserveAssetType()))
		maid:GiveTask(self._assetKeyToAssetConfig:Add(gameAssetConfig, gameAssetConfig:ObserveAssetKey()))
		maid:GiveTask(self._assetIdToAssetConfig:Add(gameAssetConfig, gameAssetConfig:ObserveAssetId()))
	end))
end

function GameConfigBase:_observeAssetFolderBrio(assetType)
	return GameConfigUtils.observeAssetFolderBrio(self._obj, assetType)
end

--[=[
	Returns the game id for this profile.
	@return Observable<number>
]=]
function GameConfigBase:ObserveGameId()
	return RxAttributeUtils.observeAttribute(self._obj, GameConfigConstants.GAME_ID_ATTRIBUTE, game.GameId)
end

--[=[
	Returns the game id
	@return number
]=]
function GameConfigBase:GetGameId()
	return AttributeUtils.getAttribute(self._obj, GameConfigConstants.GAME_ID_ATTRIBUTE, game.GameId)
end

--[=[
	Returns this configuration's name
	@return string
]=]
function GameConfigBase:GetConfigName()
	return self._obj.Name
end

--[=[
	Observes this configs name
	@return Observable<string>
]=]
function GameConfigBase:ObserveConfigName()
	return RxInstanceUtils.observeProperty(self._obj, "Name")
end

function GameConfigBase:GetGameConfigAssetBinder()
	error("Not implemented")
end

return GameConfigBase