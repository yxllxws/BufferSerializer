# Buffer Serializer
### Author: yxllxwsrollin
Description:
 
BufferSerializer allows for you to handle buffers more effectively by writing and reading values to a buffer,
while removing the complexity from it. The buffer grows automatically as you write, so the size you pass
to new() is only a starting point.
 
Example Usage:
 
	local serializer = BufferSerializer.new() -- Starts at 64 bytes and grows as needed
	serializer:WriteString("Hello, world!")
	serializer:WriteUInt8(255)
	serializer:WriteInt32(-12345)
	serializer:WriteFloat32(3.14159)
	serializer:WriteBools(true, false, true) -- 3 booleans packed into 1 byte
	serializer:WriteQuantizedFloat(73.5, 0, 100) -- 2 bytes instead of 4
	serializer:WriteVector3(Vector3.new(1, 2, 3))
	serializer:WriteColor3(Color3.fromRGB(255, 128, 0))
	serializer:WriteCFrameCompact(CFrame.new(1, 2, 3) * CFrame.Angles(0, math.rad(90), 0))
	serializer:WriteEnum(Enum.Material.Grass)
	serializer:WriteArray({ 10, 20, 30 }, serializer.WriteUInt16)
 
	local buf = serializer:ToBuffer() -- Trimmed to exactly the bytes written
 
	-- Now you can send the buffer over the network or store it as needed
	local reader = BufferSerializer.fromBuffer(buf)
	local message = reader:ReadString()
	local number = reader:ReadUInt8()
	local negative = reader:ReadInt32()
	local pi = reader:ReadFloat32()
	local a, b, c = reader:ReadBools(3)
	local health = reader:ReadQuantizedFloat(0, 100)
	local vector = reader:ReadVector3()
	local colour = reader:ReadColor3()
	local cf = reader:ReadCFrameCompact()
	local material = reader:ReadEnum(Enum.Material)
	local list = reader:ReadArray(reader.ReadUInt16)
	print(message, number, negative, pi, a, b, c, health, vector, colour, cf, material, list)
