<div>
	<img width="160" alt="logo" align="left" src="https://github.com/lokopeto/Holographic-HxA/blob/master/assets/logo.png"/>
	<h3>Holographic HxA</h3>
</div>


Native Odin Obj and glTF to [HxA](https://github.com/quelsolaar/HxA) file converter. **WARNING: this is in very early 
development stage**

<p><br></p>
<p><br></p>

## Status
### OBJ
- Converts almost all files fine, in some weird cases, the texture can be corrupted, also textures modifiers has not implemented (yet)
### GLTF
- In construction!

## Setup
If dependencies was not included.. clone them out!
*take that npm!*
```bash
cd shared
git clone https://github.com/lokopeto/glTF2
cd ..
```
Put the folder on a really good spot, import to your beautiful Odin code, go break stuff!
## Run Tests
```bash
git clone https://github.com/lokopeto/The-3D-Samples
odin test .
```
The test will convert all models from a list of samples,
You can also specify a single file using:
```bash
odin test . -define:PATH="insert path here!"
```
Also, you can recursively convert a folder!
```bash
odin test . -define:RECURSIVE=true
```

## How to Basic!
```odin
Config :: struct {
	// debugging printing, ignore
	verbose: bool, 
	// flips the V in UV mapping, useful for modern api's like Vulkan
	uv_flip: bool, 
}

converter :: proc(
	 // the file path.. duuhhh
	path: string,
	cfg: Config = DEFAULT_CONFIG,
	allocator := context.allocator
)

Error :: enum {
	None,
	// error if file is not valid, bytes as input is planned
	Invalid_File, 
}
```

Enjoy!
