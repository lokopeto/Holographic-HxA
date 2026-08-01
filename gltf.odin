/*
MIT NON-AI License

Copyright (c) 2026 lokopeto
Permission is hereby granted, free of charge, to any person obtaining a copy of the software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions.

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

In addition, the following restrictions apply:

1. The Software and any modifications made to it may not be used for the purpose of training or improving machine learning algorithms,
including but not limited to artificial intelligence, natural language processing, or data mining. This condition applies to any derivatives,
modifications, or updates based on the Software code. Any usage of the Software in an AI-training dataset is considered a breach of this License.

2. The Software may not be included in any dataset used for training or improving machine learning algorithms,
including but not limited to artificial intelligence, natural language processing, or data mining.

3. Any person or organization found to be in violation of these restrictions will be subject to legal action and may be held liable
for any damages resulting from such use.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

package holo

import "core:reflect"
import "core:encoding/hxa"
import "base:runtime"
import "core:os"

import "core:bytes"
import "core:strings"
import "core:strconv"
import "core:fmt"
import gltf "shared/glTF2"

import "core:image"
import "core:image/bmp"
import "core:image/jpeg"
import "core:image/netpbm"
import "core:image/png"
import "core:image/qoi"
import "core:image/tga"


converter_gltf :: proc(data: ^gltf.Data, dir: string, cfg: Config, allocator := context.allocator) -> (out: hxa.File) {
	context.allocator = allocator
	nodes := make([dynamic]hxa.Node)

	print(
    "Asset: ",        data.asset,               " - Asset",         "\n",
    "Scene: ",        data.scene,               " - Maybe(Integer)","\n",
    "Extensions: ",   data.extensions,          " - Extensions",    "\n",
    "Extras: ",       data.extras,              " - Extras",        "\n",

    "Accessors Length: ",           len(data.accessors),      " - []Accessor",    "\n",
    "Animations Length: ",          len(data.animations),     " - []Animation",   "\n",
    "Buffers Length: ",             len(data.buffers),        " - []Buffer",      "\n",
    "Buffer Views Length: ",        len(data.buffer_views),   " - []Buffer_View", "\n",
    "Cameras Length: ",             len(data.cameras),        " - []Camera",      "\n",
    "Images Length: ",              len(data.images),         " - []Image",       "\n",
    "Materials Length: ",           len(data.materials),      " - []Material",    "\n",
    "Meshes Length: ",              len(data.meshes),         " - []Mesh",        "\n",
    "Nodes Length: ",               len(data.nodes),          " - []Node",        "\n",
    "Samplers Length: ",            len(data.samplers),       " - []Sampler",     "\n",
    "Scenes Length: ",              len(data.scenes),         " - []Scene",       "\n",
    "Skins Length: ",               len(data.skins),          " - []Skin",        "\n",
    "Textures Length: ",            len(data.textures),            " - []Texture",     "\n",
    "Extensions Used Length: ",     len(data.extensions_used),     " - []string",      "\n",
    "Extensions Required Length: ", len(data.extensions_required), " - []string",      "\n",
    sep=""
	)

	vex3Idx,
	vex2Idx: int
	uv_flip : f32le = cfg.uv_flip ? 1 : 0

	// every mesh is a object/node(hxa)
	for m, m_i in data.meshes {		
		print(
			"\n==================\n",
			"-- ",m.name," --\n",
			"Primitives Amount: ", len(m.primitives), "\n",
			"Mesh Index: ", m_i,
			sep=""
		)
		p_i3,
		p_i2: int
		for p, p_i in m.primitives {
			p_i3 = p_i * 3
			p_i2 = p_i * 2

			// print(p.attributes)
			// position	:= new(gltf.Buffer_Slice)
			// normal 		:= new(gltf.Buffer_Slice)
			// texCoord0 := new(gltf.Buffer_Slice)
							
			indices      := gltf.buffer_slice(data,p.indices.(gltf.Integer))
			array_size   := len(indices.([]u16le))
			vertex_totalExp := array_size * 3
			vertex_total := array_size
			has_material := p.material == nil ? false : true

			position   := make([]f32le,vertex_totalExp)
			normal     := make([]f32le,vertex_totalExp)
			uv         := make([]f32le,vertex_total * 2)
			
			position_raw := gltf.buffer_slice(data,p.attributes["POSITION"])
			normal_raw   := gltf.buffer_slice(data,p.attributes["NORMAL"])
			uv_raw       := gltf.buffer_slice(data,p.attributes["TEXCOORD_0"])
			mat_raw: gltf.Buffer_Slice
			if has_material {
				mat_raw = gltf.buffer_slice(data,p.material.(gltf.Integer))
			}

			for idc,idc_i in indices.([]u16le) {
				vex3Idx = idc_i * 3
				vex2Idx = idc_i * 2

				position[vex3Idx  ],
				position[vex3Idx+1],
				position[vex3Idx+2] = expand_values(position_raw.([][3]f32le)[idc])

				normal[vex3Idx  ],
				normal[vex3Idx+1],
				normal[vex3Idx+2] = expand_values(normal_raw.([][3]f32le)[idc])

				uv[vex2Idx  ] = uv_raw.([][2]f32le)[idc].x
				uv[vex2Idx+1] = uv_flip - uv_raw.([][2]f32le)[idc].y
			}

			// print(mat_raw)
			// print(position_comp, normal_comp, texCoord0_comp)

			vertex := make(hxa.Layer_Stack, 3)
			vertex[0] = {
				name = 			 hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_NAME,
				components = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_COMPONENTS,
				data = position
			} 			
			vertex[1] = {
				name = hxa.CONVENTION_SOFT_LAYER_NORMALS,
				components = 3,
				data = normal
			}
			vertex[2] = {
				name = "uv",
				components = 2,
				data = uv
			}
			// vertex[3] = {
			// 	name = "mat_idx",
			// 	components = 2,
			// 	data = make([]i32le, 4)
			// }


			print("position:  ", reflect.union_variant_typeid(position_raw),  len(position_raw.([][3]f32le)) )
			print("normal:    ", reflect.union_variant_typeid(normal_raw),    len(normal_raw.([][3]f32le))   )
			print("texCoord0: ", reflect.union_variant_typeid(uv_raw), len(uv_raw.([][2]f32le)))
			print(p)


			model_node := new(hxa.Node, allocator)
			// model_node: hxa.Node
			model_node.content = hxa.Node_Geometry{
				vertex_stack = vertex,
				vertex_count = u32le(vertex_total),
			}
			
			model_node.meta_data = make([]hxa.Meta, 1)
			model_node.meta_data[0] = {
				name = "type",
				value = "vertex"
			}
			append(&nodes, model_node^)
		}
		
		// mesh primitives is weird, each primitive is a texture index
		// merge all togetter or split? give that as a option?

	}

	out.nodes = nodes[:]
	return
}
