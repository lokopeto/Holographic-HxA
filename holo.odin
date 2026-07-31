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

import "core:sort"
import "core:mem"
import "core:relative"
import "core:testing"
import "core:time"
import "core:encoding/hxa"
import gltf "shared/glTF2"
import "base:runtime"
import "core:os"

import "core:bytes"
import "core:strings"
import "core:strconv"
import "core:fmt"

import "core:image"
import "core:image/bmp"
import "core:image/jpeg"
import "core:image/netpbm"
import "core:image/png"
import "core:image/qoi"
import "core:image/tga"

@(private) print := fmt.println


/*
	The OBJ Loader was adapted from Sven Woldt/algo-boyz tinyobj,
	without them, it would be harder to get going!
	https://github.com/algo-boyz/tinyobj
*/

INVALID_INDEX    		:= 0x80000000
INVALID_INDEX_LE    := i32le(INVALID_INDEX)

Material :: struct {
	name:                       string,
	ambient:                    [3]f64le,
	diffuse:                    [3]f64le,
	specular:                   [3]f64le,
	transmittance:              [3]f64le,
	emission:                   [3]f64le,
	shininess:                  f64le,
	ior:                        f64le, // index of refraction
	dissolve:                   f64le, // 1 == opaque; 0 == fully transparent
	illum:                      i64le,
	
	// Texture maps
	ambient_texname:            string, // map_Ka
	diffuse_texname:            string, // map_Kd
	specular_texname:           string, // map_Ks
	specular_highlight_texname: string, // map_Ns
	bump_texname:               string, // map_bump, bump
	displacement_texname:       string, // disp
	alpha_texname:              string, // map_d
}

Shape :: struct {
	name:        string,
	face_offset: int,
	length:      int,
}

Vertex_Index :: struct {
	v_idx:  i32le,
	vt_idx: i32le,
	vn_idx: i32le,
}

Attrib :: struct {
	vertices:       [dynamic][3]f32le,
	normals:        [dynamic][3]f32le,
	texcoords:      [dynamic][2]f32le,
	faces:          [dynamic]Vertex_Index,
	face_num_verts: [dynamic]i32le,
	material_ids:   [dynamic]i32le,
}


// OBJ format uses 1-based indexing, and negative values for relative indexing.
// This converts them to 0-based absolute indices.
@(private)
fix_index :: proc(idx: i32le, n: i32le) -> i32le {
	if idx > 0 do return idx - 1
	if idx == 0 do return 0
	return n + idx
}

@(private)
parse_float32 :: proc(s: string) -> f32le {
	val, _ := strconv.parse_f32(s)
	return f32le(val)
}
@(private)
parse_float64 :: proc(s: string) -> f64le {
	val, _ := strconv.parse_f64(s)
	return f64le(val)
}

@(private)
parse_int32 :: proc(s: string) -> i32le {
	val, _ := strconv.parse_int(s)
	return i32le(val)
}
@(private)
parse_int64 :: proc(s: string) -> i64le {
	val, _ := strconv.parse_int(s)
	return i64le(val)
}
@(private)
init_material :: proc() -> Material {
	m: Material
	m.dissolve = 1.0
	m.shininess = 1.0
	m.ior = 1.0
	return m
}
@(private)
commit_shape :: proc(shapes: ^[dynamic]Shape, name: string, offset: int, length: int) {
	if length > 0 {
		shape: Shape
		shape.name = strings.clone(name)
		shape.face_offset = offset
		shape.length = length
		append(shapes, shape)
	}
}

parse_mtl_file :: proc(filename: string, alloc := context.allocator) -> ([dynamic]Material, map[string]i32le, bool) {
	context.allocator = alloc
	data, ok := os.read_entire_file(filename,context.allocator)
	if ok != os.General_Error.None {
		fmt.eprintln("TINYOBJ: Error reading material file:", filename)
		return nil, nil, false
	}
	defer delete(data)

	content := string(data)
	materials := make([dynamic]Material)
	mat_map := make(map[string]i32le)

	current_mat := init_material()
	has_current := false

	for line in strings.split_lines_iterator(&content) {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || trimmed[0] == '#' do continue

		parts := strings.fields(trimmed)
		parts_len := len(parts)
		defer delete(parts)
		if parts_len == 0 do continue

		token := parts[0]

		switch token {
		case "newmtl":
			if parts_len > 1 {
				if has_current {
					append(&materials, current_mat)
					mat_map[current_mat.name] = i32le(len(materials) - 1)
				}
				current_mat = init_material()
				current_mat.name = strings.clone(parts[1])
				has_current = true
			}
		case "Ka":
			if parts_len >= 4 {
				current_mat.ambient[0] = parse_float64(parts[1])
				current_mat.ambient[1] = parse_float64(parts[2])
				current_mat.ambient[2] = parse_float64(parts[3])
			}
		case "Kd":
			if parts_len >= 4 {
				current_mat.diffuse[0] = parse_float64(parts[1])
				current_mat.diffuse[1] = parse_float64(parts[2])
				current_mat.diffuse[2] = parse_float64(parts[3])
			}
		case "Ks":
			if parts_len >= 4 {
				current_mat.specular[0] = parse_float64(parts[1])
				current_mat.specular[1] = parse_float64(parts[2])
				current_mat.specular[2] = parse_float64(parts[3])
			}
		case "Kt", "Tf":
			if parts_len >= 4 {
				current_mat.transmittance[0] = parse_float64(parts[1])
				current_mat.transmittance[1] = parse_float64(parts[2])
				current_mat.transmittance[2] = parse_float64(parts[3])
			}
		case "Ni":
			if parts_len >= 2 do current_mat.ior = parse_float64(parts[1])
		case "Ke":
			if parts_len >= 4 {
				current_mat.emission[0] = parse_float64(parts[1])
				current_mat.emission[1] = parse_float64(parts[2])
				current_mat.emission[2] = parse_float64(parts[3])
			}
		case "Ns":
			if parts_len >= 2 do current_mat.shininess = parse_float64(parts[1])
		case "d":
			if parts_len >= 2 do current_mat.dissolve = parse_float64(parts[1])
		case "Tr":
			if parts_len >= 2 do current_mat.dissolve = 1.0 - parse_float64(parts[1])
		case "illum":
			if parts_len >= 2 do current_mat.illum = parse_int64(parts[1])
		case "map_Ka":
			if parts_len >= 2 do current_mat.ambient_texname = strings.clone(parts[parts_len-1])
		case "map_Kd":
			if parts_len >= 2 do current_mat.diffuse_texname = strings.clone(parts[parts_len-1])
		case "map_Ks":
			if parts_len >= 2 do current_mat.specular_texname = strings.clone(parts[parts_len-1])
		case "map_Ns":
			if parts_len >= 2 do current_mat.specular_highlight_texname = strings.clone(parts[parts_len-1])
		case "map_bump", "bump":
			if parts_len >= 2 do current_mat.bump_texname = strings.clone(parts[parts_len-1])
		case "disp":
			if parts_len >= 2 do current_mat.displacement_texname = strings.clone(parts[parts_len-1])
		case "map_d":
			if parts_len >= 2 do current_mat.alpha_texname = strings.clone(parts[parts_len-1])
		}
	}

	if has_current {
		append(&materials, current_mat)
		mat_map[current_mat.name] = i32le(len(materials) - 1)
	}

	return materials, mat_map, true
}

converter_obj :: proc(data: []byte, dir: string, cfg: Config, allocator := context.allocator) -> (out: hxa.File) {
	verb := proc(args: ..any, sep := " ", flush := true) -> int { return 0 }
	if cfg.verbose == true {
		verb = print
	}

	context.allocator = allocator // Is that legal?
	out.allocator = allocator


	// TODO: WOLOLO..
	//      *translation: rewrite that to hxa structs*
	nodes := make([dynamic]hxa.Node)
	vertices := make([dynamic][3]f32le)
	normals := make([dynamic][3]f32le)
	texcoords := make([dynamic][2]f32le)
	faces := make([dynamic]Vertex_Index)
	material_ids := make([dynamic]i32le)
	shapes := make([dynamic]Shape)
	materials := make([dynamic]Material)

	// Lookup for materials
	mat_map := make(map[string]i32le)
	defer delete(mat_map)

	current_material_id : i32le = -1
	
	// Shape tracking
	current_shape_name := ""
	face_count := 0
	prev_shape_face_offset := 0

	// Counts for relative indexing
	v_count  : i32le = 0
	vn_count : i32le = 0
	vt_count : i32le = 0

	it := string(data)
	for line in strings.split_lines_iterator(&it) {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || trimmed[0] == '#' do continue

		parts := strings.fields(trimmed)
		defer delete(parts)
		if len(parts) == 0 do continue

		token := parts[0]

		switch token {
		case "v":
			if len(parts) >= 4 {
				append(&vertices,  [3]f32le{parse_float32(parts[1]), parse_float32(parts[2]), parse_float32(parts[3])})
				v_count += 1
			}
		case "vn":
			if len(parts) >= 4 {
				append(&normals, 	 [3]f32le{parse_float32(parts[1]), parse_float32(parts[2]), parse_float32(parts[3])})
				vn_count += 1
			}
		case "vt":
			if len(parts) >= 3 {
				append(&texcoords, [2]f32le{parse_float32(parts[1]), parse_float32(parts[2])})
				vt_count += 1
			}
		case "f":
			// Parse raw face indices first
			face_indices := make([dynamic]Vertex_Index, 0, 4)
			defer delete(face_indices)

			for i := 1; i < len(parts); i += 1 {
				vi: Vertex_Index
				vi.v_idx = 	INVALID_INDEX_LE
				vi.vt_idx = INVALID_INDEX_LE
				vi.vn_idx = INVALID_INDEX_LE

				segment := parts[i]
				slashes := strings.split(segment, "/")
				defer delete(slashes)

				// Format: v, v/vt, v/vt/vn, v//vn

				if len(slashes) >= 1 && len(slashes[0]) > 0 {
					vi.v_idx = fix_index(parse_int32(slashes[0]), v_count)
				}
				if len(slashes) >= 2 && len(slashes[1]) > 0 {
					vi.vt_idx = fix_index(parse_int32(slashes[1]), vt_count)
				}
				if len(slashes) >= 3 && len(slashes[2]) > 0 {
					vi.vn_idx = fix_index(parse_int32(slashes[2]), vn_count)
				}
				append(&face_indices, vi)
			}
			// Triangulation Logic
			if len(face_indices) > 3 {
				i0 := face_indices[0]
				// Fan triangulation
				for k := 2; k < len(face_indices); k += 1 {
					i1 := face_indices[k-1]
					i2 := face_indices[k  ]
					
					append(&faces, i0)
					append(&faces, i1)
					append(&faces, i2)
					
					append(&material_ids, current_material_id)
					face_count += 1
				}
			}

		case "usemtl":
			if len(parts) >= 2 {
				name := parts[1]
				if id, ok := mat_map[name]; ok {
					current_material_id = id
				} else {
					current_material_id = -1
				}
				print(mat_map)
				print(current_material_id)
			}

		case "mtllib":
			if len(parts) >= 2 {
				fname := parts[1]
				full_path := fname
				if len(dir) > 0 {
					full_path, _ = os.join_path({dir, fname}, context.allocator)
				}
				
				// Parse MTL
				new_mats, new_map, ok := parse_mtl_file(full_path)
				if ok {
					// Merge materials
					start_idx := i32le(len(materials))
					for m in new_mats {
						append(&materials, m)
					}
					// Merge map with offset
					for name, local_idx in new_map {
						mat_map[name] = start_idx + local_idx
					}
					delete(new_mats)
					delete(new_map)
				}
				if len(dir) > 0 {
					delete(full_path)
				}
			}

		case "o", "g":
			if len(parts) >= 2 {
				// Commit previous shape
				if face_count > prev_shape_face_offset {
					commit_shape(&shapes, current_shape_name, prev_shape_face_offset, face_count - prev_shape_face_offset)
					prev_shape_face_offset = face_count
				}
				current_shape_name = parts[1]
			}
		}
	}
	// Commit last shape
	if face_count > prev_shape_face_offset {
		commit_shape(&shapes, current_shape_name, prev_shape_face_offset, face_count - prev_shape_face_offset)
	}
	
	
	vertex := make(hxa.Layer_Stack, 4)
	vertex[0] = {
		name = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_NAME,
		components = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_COMPONENTS,
		data = make([]f32le, len(faces)*3)
	} 
	vertex[1] = {
		name = hxa.CONVENTION_SOFT_LAYER_NORMALS,
		components = 3,
		data = make([]f32le, len(faces)*3)
	}
	vertex[2] = {
		name = "uv",
		components = 2,
		data = make([]f32le, len(faces)*2)
	}
	vertex[3] = {
		name = "mat_idx",
		components = 2,
		data = make([]i32le, len(faces)*2)
	}

	// I know, thats not's C..
	position_index, 
	normals_index, 
	uv_index, 
	tex_index, 
	vertex_index3,
	vertex_index2: int

	normals_len := len(normals)
	uv_len 			:= len(texcoords)
	mat_len 		:= len(materials)
	faces_len 	:= len(faces)
	matid_len		:= len(material_ids)

	if cfg.verbose {
		print("	","Materials: ", 			 len(materials))
		print("	","Material IDs: ",    len(material_ids))
		print("	","Faces: ",           len(faces))
		print("	","Vertices: ",        len(vertices))
		print("	","Normals: ",         len(normals))
		if len(texcoords) > 0 {
			print("	","Texcoords: ",     len(texcoords))
		}
	}
	/*
	print(data.materials)
	if len(data.materials) > 0 {
		if len(data.materials) > 100 {
		}
			// print("HEY, THATS WEIRD!!!")
			uniqueNumbers : [10000]i32le
			for m_id in material_ids {
				uniqueNumbers[m_id] += 1
			}
			for unique, unique_i in uniqueNumbers {
				if unique > 0 {
					print("[",unique_i,"]", unique, sep="")
				}
			}
			// print(data.materials[50:51])
	}
	*/

	matID_used : [dynamic]i32le
	matID_past : i32le 
	matProcessed : map[i32le]bool
		
	{ verb("-Process Vertices")
	mat_id : i32le
	uv_flip : f32le = cfg.uv_flip ? 1 : 0

	for f, f_i in faces {
		tex_index = int(f32(f_i) / 3.0)

		vertex_index3 = f_i * 3
		vertex_index2 = f_i * 2
	
		vertex[0].data.([]f32le)[vertex_index3    ],
		vertex[0].data.([]f32le)[vertex_index3 + 1],
		vertex[0].data.([]f32le)[vertex_index3 + 2] = expand_values(vertices[f.v_idx])

		if normals_index < normals_len && f.vn_idx != INVALID_INDEX_LE {
			vertex[1].data.([]f32le)[vertex_index3    ],
			vertex[1].data.([]f32le)[vertex_index3 + 1],
			vertex[1].data.([]f32le)[vertex_index3 + 2] = expand_values(normals[f.vn_idx])
		}

		if f.vt_idx != INVALID_INDEX_LE {
			vertex[2].data.([]f32le)[vertex_index2    ] = texcoords[f.vt_idx].x
			vertex[2].data.([]f32le)[vertex_index2 + 1] = uv_flip - texcoords[f.vt_idx].y
		}
		
		if tex_index < matid_len {
			mat_id = material_ids[tex_index]

			if mat_id != matID_past {
				// verb("Unique MatID", mat_id)
				append(&matID_used, mat_id)
			}
			matID_past = material_ids[tex_index]
		}
	}

	}; verb("-Processed")

	verb("-Make Vertex Node")
	model_node := new(hxa.Node)
	// model_node: hxa.Node
	model_node.content = hxa.Node_Geometry{
		vertex_stack = vertex,
		vertex_count = u32le(len(faces)),
	}
	
	model_node.meta_data = make([]hxa.Meta, 1)
	model_node.meta_data[0] = {
		name  = "type",
		value = "vertex"
	}
	verb("-Append")
	append(&nodes, model_node^)

	// if cfg.verbose {
	// 	for m, m_i in matID_used {
	// 		print("[",m_i,"]", m, sep="")
	// 	}
	// }

	matID_remap: map[i32le][2]i32le
	if mat_len > 0 { 
		verb("-Process Materials")
		node_off := len(nodes)
		img_idx: u32le
		mat: Material
		imagePaths_unique: map[string][2]u32le // {bool, index}
		node_metadata := make([dynamic][dynamic]hxa.Meta) // [node_index][metadata_node]
		// i know, its a little ugly, but i think will work fine for now!
		for mat_id, mat_i in matID_used {
			// handle relative index
			if mat_id < 0 { continue }
			mat = materials[mat_id]
			if len(mat.diffuse_texname) <= 0 { continue }
	
			if imagePaths_unique[mat.diffuse_texname].x == 0 {
				verb("Mat ", mat_i, ": ", mat.name, sep="")
		
				// read texture
				verb("Diffuse:", mat.diffuse_texname)
				diff_img, diff_err := img_load(dir, mat.diffuse_texname)
				if diff_err != .None { continue }
				

				verb("-Make Image Node")
				tex := new(hxa.Node)
				
				img_layers := make(hxa.Layer_Stack, 1)
				img_layers[0] = {
					components = 4,
					name = hxa.CONVENTION_SOFT_ALBEDO,
					data = bytes.buffer_to_bytes(&diff_img.pixels)
				}
		
				tex.content = hxa.Node_Image{
					resolution = {u32le(diff_img.width), u32le(diff_img.height), 1},
					type = .Image_2D,
					image_stack = img_layers
				}
				
				metadata := make([dynamic]hxa.Meta)
				
				append(&metadata, hxa.Meta{
					name = "type",
					value = "texture"
				})
				append(&metadata, hxa.Meta{
					name = hxa.CONVENTION_SOFT_LAYER_MATERIAL_ID,
					value = mat_node(&mat)
				})
				
				append(&node_metadata, metadata)
				append(&nodes, tex^)
				verb("-Append")
	
				matID_remap[i32le(mat_id)] = {i32le(img_idx), 2}
				imagePaths_unique[mat.diffuse_texname] = {1,img_idx}
				img_idx += 1
			} else {

				if matID_remap[i32le(mat_id)].x == 0 {
					append(&node_metadata[imagePaths_unique[mat.diffuse_texname].y], hxa.Meta{
						name = hxa.CONVENTION_SOFT_LAYER_MATERIAL_ID,
						value = mat_node(&mat)
					})
	
					matID_remap[i32le(mat_id)] = {i32le(imagePaths_unique[mat.diffuse_texname].y), i32le(len(node_metadata[imagePaths_unique[mat.diffuse_texname].y]))}
				}
			}
		}
		
		for nm, nm_i in node_metadata {
			nodes[node_off + nm_i].meta_data = nm[:]
		}
	
		if cfg.verbose {
			print("Node Metadata Length: ",len(node_metadata[:]))
			for nmt, nmt_i in node_metadata {
				print(" Meta ",nmt_i,": ",len(nmt[:]), sep="")
			}
			for mid_i, mid in matID_remap {
				print(" Remap ",mid_i,": ",mid, sep="")
			}
		} // cfg.verbose
	} // Process Materials

	verb("-Finalize Materials")
	for idx in 0..<faces_len {
		tex_index = int(f32(idx) / 3.0)
		if tex_index < matid_len {
			vertex_index2 = idx * 2
			vertex[3].data.([]i32le)[vertex_index2		],
			vertex[3].data.([]i32le)[vertex_index2 + 1] = expand_values(matID_remap[material_ids[tex_index]])
		} else {
			break
		}
	}
	out.nodes = nodes[:]


	//Free Mem
	delete(vertices)
	delete(normals)
	delete(texcoords)
	delete(faces)
	delete(material_ids)
	
	for s in shapes do delete(s.name)
	delete(shapes)

	for m in materials {
		delete(m.name)
		if len(m.ambient_texname) > 0 do delete(m.ambient_texname)
		if len(m.diffuse_texname) > 0 do delete(m.diffuse_texname)
        if len(m.specular_texname) > 0 do delete(m.specular_texname)
        if len(m.specular_highlight_texname) > 0 do delete(m.specular_highlight_texname)
        if len(m.bump_texname) > 0 do delete(m.bump_texname)
        if len(m.displacement_texname) > 0 do delete(m.displacement_texname)
        if len(m.alpha_texname) > 0 do delete(m.alpha_texname)
	}
	delete(materials)

	return
}
converter_gltf :: proc(data: ^gltf.Data, dir: string, cfg: Config, allocator := context.allocator) -> (out: hxa.File) {
	context.allocator = allocator
	nodes := make([dynamic]hxa.Node)

	// every mesh is a object/node(hxa)
	for m, i in data.meshes {		
		print(
			"\n==================\n",
			"-- ",m.name," --\n",
			"Primitives Amount: ",len(m.primitives),"\n",
			"Mesh Index: ",i,
			"\n==================\n", sep="")

		p_i3,
		p_i2: int
		for p, p_i in m.primitives {
			p_i3 = p_i * 3
			p_i2 = p_i * 2
			
			// vertex := make(hxa.Layer_Stack, 4, allocator)
			// vertex[0] = {
			// 	name = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_NAME,
			// 	components = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_COMPONENTS,
			// 	data = make([]f32le, len(obj.attrib.faces)*3, allocator)
			// }
			// vertex[1] = {
			// 	name = hxa.CONVENTION_SOFT_LAYER_NORMALS,
			// 	components = 3,
			// 	data = make([]f32le, len(obj.attrib.faces)*3, allocator)
			// }
			// vertex[2] = {
			// 	name = "uv",
			// 	components = 2,
			// 	data = make([]f32le, len(obj.attrib.faces)*2, allocator)
			// }
			// vertex[3] = {
			// 	name = "tex_i",
			// 	components = 1,
			// 	data = make([]i32le, len(obj.attrib.faces), allocator)
			// }

			// print(p.attributes)
			position := gltf.buffer_slice(data,p.attributes["POSITION"])
			normal := gltf.buffer_slice(data,p.attributes["NORMAL"])
			texCoord_0 := gltf.buffer_slice(data,p.attributes["TEXCOORD_0"])
			
			print(len(position.([][3]f32)))
			print(len(normal.([][3]f32)))
			print(len(texCoord_0.([][2]f32)))
			print(position.([][3]f32))
			
			


			// model_node := new(hxa.Node, allocator)
			// // model_node: hxa.Node
			// model_node.content = hxa.Node_Geometry{
			// 	vertex_stack = vertex,
			// 	vertex_count = u32le(len(obj.attrib.faces)),
			// }
			
			// model_node.meta_data = make([]hxa.Meta, 1)
			// model_node.meta_data[0] = {
			// 	name = "type",
			// 	value = "vertex"
			// }
			// append(&nodes, model_node^)
		}

		//mesh primitive index ->
		//acessor index ->
		//buffer view index ->
		//buffer = the beautiful data

		// mesh primitives is weird, each primitive is a texture index
		// merge all togetter or split? give that as a option?

	}

	// for data_byte in data.buffers[meshPos_buffView.buffer].uri.([]byte)[mesh_off:mesh_len] {
	// 	print(data_index)
	// 	data_index = (data_index + 1) % max()
	// }
	out.nodes = nodes[:]
	return
}


Error :: enum {
	None,
	Invalid_File,
}
Config :: struct {
	verbose: bool,
	uv_flip: bool,
}
DEFAULT_CONFIG :: Config{
	verbose = false,
	uv_flip = false,
}
converter :: proc(
		path: string,
		cfg: Config = DEFAULT_CONFIG,
		allocator := context.allocator
	) -> ( out: hxa.File, err: Error ) {
	verb := proc(args: ..any, sep := " ", flush := true) -> int { return 0 }
	if cfg.verbose == true { verb = print }
	context.allocator = allocator
	dir, ext := os.dir(path), os.ext(path)
	ext = strings.to_lower(ext)
	file, file_err := os.read_entire_file(path, allocator)
	
	if file_err == os.General_Error.None {
		verb("Path:", path)
		verb("Dir/Ext:", dir, ext)
		switch ext {
			case ".obj":
				verb("-Parse OBJ")
				
				verb("-Convert")
				out = converter_obj(file, dir, cfg)

				return
			case ".gltf", ".glb":
				verb("-Parse GLTF/GLB")
		    options := gltf.Options {
	        delete_content = true,
	        gltf_dir       = dir,
					is_glb				 = ext == ".glb"
		    }
				data, parse_err := gltf.parse(file, options)

				verb("-Convert")
				out = converter_gltf(data, dir, cfg)
				/*
				*/
				return
			case:
				verb("File Error:", "Invalid Ext")
				delete(file[:])
				return out, .Invalid_File
		}
	}

	verb("File Error:", file_err)
	delete(file[:])
	return out, .Invalid_File
}

@(test)
main_test :: proc (T: ^testing.T) {
	allow_recursive := #config(RECURSIVE, false)
	model_path := #config(PATH, "")
	if model_path == "" {
		allow_recursive = true
		model_path = "The-3D-Samples"
	}
	

	if allow_recursive {
		walk := os.walker_create(model_path)
		for w in os.walker_walk(&walk) {
			if w.type == .Regular {
				wd, _ := os.get_working_directory(context.temp_allocator)
				relative_path, _ := os.get_relative_path(wd,w.fullpath, context.temp_allocator)
				loadModel_test(T,relative_path)
				free_all(context.temp_allocator)
			}
		}
		os.walker_destroy(&walk)
	} else {
		loadModel_test(T,model_path)
	}
	
	make_folder_recursive :: proc(path_out, path: string, alloc := context.temp_allocator) -> string {
		path_split, _ := strings.split_after_n(os.dir(path), os.Path_Separator_String, 2, alloc)
		path_split[0] = path_out
		out := strings.join(path_split, os.Path_Separator_String, alloc)
		os.make_directory_all(out)
		return out
	}
	
	loadModel_test :: proc(T: ^testing.T,path: string) {
		context.allocator = context.temp_allocator
		readobj_time,
		conversion_time,
		read_time   				 : time.Time
		readobj_duration,
		conversion_duration,
		read_duration   		 : time.Duration
	
		conversion_time = time.now()
		
		print("-- Converter --")
		modelhxa, model_err := converter(path, {
			verbose = true,
			uv_flip = true
		}, context.allocator);
		if model_err != .None { return }

		
		defer hxa.file_destroy(modelhxa)
	
		out_path := make_folder_recursive("out", path)
		out_file := strings.join(
			{	
				out_path, 
					os.Path_Separator_String, 
				os.base(path[:len(path) - len(os.long_ext(path))]),
					".hxa"
			},
			sep="")
		print("Output Path:",out_file)
		
		write_err := hxa.write_to_file(out_file, modelhxa)
		conversion_duration	= time.diff(conversion_time, time.now())
		print("Duration:", conversion_duration,", Status: ", write_err, "\n", sep="")
		
		read_time = time.now()
		out_read, read_err := hxa.read_from_file(out_file, true)
		defer hxa.file_destroy(out_read)

		read_duration	= time.diff(read_time, time.now())

		testing.expect(T, out_read.magic_number == hxa.MAGIC_NUMBER)
		// testing.expect(T,out_read.internal_node_count > 0)
		testing.expect(T, out_read.version == hxa.LATEST_VERSION)
		testing.expect(T, len(out_read.backing) > 0)

		testing.expect(T, len(out_read.nodes) == len(modelhxa.nodes))
		testing.expect(T, read_err == .None)

		print("-- Read --")
		print("Node Length:",len(out_read.nodes))
		print("Internal Node Count:",out_read.internal_node_count)
		print("Duration:", read_duration, ", Status: ", read_err, sep="")
		print("----")
	}
}


//Procs that no one cares:

// Convert a material from tinyobj to a nested hxa node 
@(private)
mat_node :: proc(
	mat: ^Material, 
	alloc := context.allocator
	) -> (meta: []hxa.Meta) {	
	meta = make([]hxa.Meta, 17, alloc)
	meta[0] = {
		name = "name",
		value = mat.name,
	}
	meta[1] = {
		name = "ambient",
		value = mat.ambient[:],
	}
	meta[2] = {
		name = "diffuse",
		value = mat.diffuse[:],
	}
	meta[3] = {
		name = "specular",
		value = mat.specular[:],
	}
	meta[4] = {
		name = "transmittance",
		value = mat.transmittance[:],
	}
	meta[5] = {
		name = "emission",
		value = mat.emission[:],
	}
	meta[6] = {
		name = "shininess",
		value = []f64le{mat.shininess},
	}
	meta[7] = {
		name = "ior",
		value = []f64le{mat.ior},
	}
	meta[8] = {
		name = "dissolve",
		value = []f64le{mat.dissolve},
	}
	meta[9] = {
		name = "illum",
		value = []i64le{mat.illum},
	}
	meta[10] = {
		name = "ambient_texname",
		value = mat.ambient_texname,
	}
	meta[11] = {
		name = "diffuse_texname",
		value = mat.diffuse_texname,
	}
	meta[12] = {
		name = "specular_texname",
		value = mat.specular_texname,
	}
	meta[13] = {
		name = "specular_highlight_texname",
		value = mat.specular_highlight_texname,
	}
	meta[14] = {
		name = "bump_texname",
		value = mat.bump_texname,
	}
	meta[15] = {
		name = "displacement_texname",
		value = mat.displacement_texname,
	}
	meta[16] = {
		name = "alpha_texname",
		value = mat.alpha_texname,
	}
	return
}

ImageLoadError :: enum {
	None,
	File_Load_Error,
	Image_Decoding_Error,
}
img_load :: proc(dir, path: string, allocator := context.allocator) -> (img: ^image.Image, err: ImageLoadError) {
	img_options := image.Options{.alpha_add_if_missing}
	img_path, _ := os.join_path({dir,path}, allocator)
	img_path, _ = os.replace_path_separators(img_path, os.Path_Separator, allocator)
	
	read_err: image.Error
	img, read_err = image.load_from_file(img_path, img_options)
	if read_err == .Unable_To_Read_File {
		files, folder_err := os.read_directory_by_path(dir, 0, allocator)
		if folder_err != os.General_Error.None {
			err = .File_Load_Error
			return
		}
		str := strings.to_upper_snake_case(path)
		read_err : image.Error
		for f in files {
			str_entry := strings.to_upper_snake_case(f.name)
			if str_entry == str {
				img, read_err = image.load_from_file(f.fullpath, img_options)
				return
			}
		}
		for f in files {
			str_entry := os.stem(f.name)
			img, read_err = image.load_from_file(f.fullpath, img_options)
			return
		}
		if read_err != image.General_Image_Error.None {
			err = .Image_Decoding_Error
			return
		}
	}
	return
}
