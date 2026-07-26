package main

import "vendor:glfw"
import "core:time"
import "core:encoding/json"
import "core:encoding/hxa"
import "shared/tinyobj"
import gltf "shared/glTF2"
import "base:runtime"
import "core:os"

import "core:bytes"
import "core:strings"
import "core:fmt"

import "core:image"
import "core:image/bmp"
import "core:image/jpeg"
import "core:image/netpbm"
import "core:image/png"
import "core:image/qoi"
import "core:image/tga"

@(private) print := fmt.println

modelConverter_hxa :: proc(path: string, allocator := context.allocator) -> (out: hxa.File) {
	dir, ext := os.dir(path), os.ext(path)
	data, err := os.read_entire_file(path, allocator)
	
	if err == os.General_Error.None {
		nodes := make([dynamic]hxa.Node)
		switch ext {
			case ".obj":
				obj := tinyobj.parse_obj(string(data), dir, tinyobj.FLAG_TRIANGULATE)
				defer tinyobj.destroy(&obj)

				vertex := make(hxa.Layer_Stack, 4, allocator)
				vertex[0] = {
					name = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_NAME,
					components = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_COMPONENTS,
					data = make([]f32le, len(obj.attrib.faces)*3, allocator)
				}
				vertex[1] = {
					name = hxa.CONVENTION_SOFT_LAYER_NORMALS,
					components = 3,
					data = make([]f32le, len(obj.attrib.faces)*3, allocator)
				}
				vertex[2] = {
					name = "uv",
					components = 2,
					data = make([]f32le, len(obj.attrib.faces)*2, allocator)
				}
				vertex[3] = {
					name = "tex_i",
					components = 1,
					data = make([]i32le, len(obj.attrib.faces), allocator)
				}

				// m.vertex = make([]Vertex, len(obj.attrib.faces), allocator)
				// print(obj.attrib.faces)
				position_index, 
				normals_index, 
				uv_index, 
				tex_index, 
				vertex_index3,
				vertex_index2: int

				normals_len := len(obj.attrib.normals)
				uv_len := len(obj.attrib.texcoords)
				/*
				*/
				for i in 0..<len(obj.attrib.faces) {
					position_index = obj.attrib.faces[i].v_idx * 3
					normals_index = obj.attrib.faces[i].vn_idx * 3
					uv_index = obj.attrib.faces[i].vt_idx * 2
					tex_index = int(f32(i) / 3.0)

					vertex_index3 = i * 3
					vertex_index2 = i * 2
					// print(position_index, position_index + 1, position_index + 2)
				
					vertex[0].data.([]f32le)[vertex_index3    ] = f32le(obj.attrib.vertices[position_index    ])
					vertex[0].data.([]f32le)[vertex_index3 + 1] = f32le(obj.attrib.vertices[position_index + 1])
					vertex[0].data.([]f32le)[vertex_index3 + 2] = f32le(obj.attrib.vertices[position_index + 2])

					if normals_index < normals_len {
						vertex[1].data.([]f32le)[vertex_index3    ] = f32le(obj.attrib.normals[normals_index		])
						vertex[1].data.([]f32le)[vertex_index3 + 1] = f32le(obj.attrib.normals[normals_index + 1])
						vertex[1].data.([]f32le)[vertex_index3 + 2] = f32le(obj.attrib.normals[normals_index + 2])
					}

					vertex[2].data.([]f32le)[vertex_index2    ] = f32le(    obj.attrib.texcoords[uv_index    ])
					vertex[2].data.([]f32le)[vertex_index2 + 1] = f32le(1 - obj.attrib.texcoords[uv_index + 1])
					
					if tex_index < len(obj.attrib.material_ids){
						vertex[3].data.([]i32le)[i] = i32le(obj.attrib.material_ids[tex_index])
					}
				}

				// probably that's not needed
				// vertex_count: u32le
				// for k in vertex {
				// 	l: u32le
				// 	switch v in k.data {
				// 		case []u8:
				// 			l = u32le(len(k.data.([]u8)))
				// 		case []i32le:
				// 			l = u32le(len(k.data.([]i32le)))
				// 		case []f32le:
				// 			l = u32le(len(k.data.([]f32le)))
				// 		case []f64le:
				// 			l = u32le(len(k.data.([]f64le)))
				// 	}
				// 	vertex_count += u32le(k.components)
				// }

				model_node := new(hxa.Node, allocator)
				// model_node: hxa.Node
				model_node.content = hxa.Node_Geometry{
					vertex_stack = vertex,
					vertex_count = u32le(len(obj.attrib.faces)),
				}
				
				model_node.meta_data = make([]hxa.Meta, 1)
				model_node.meta_data[0] = {
					name = "type",
					value = "vertex"
				}
				append(&nodes, model_node^)
				/*
				*/
				for mat, mat_i in obj.materials {
					if len(mat.diffuse_texname) <= 0 { continue }

					// read texture
					img_options := image.Options{.alpha_add_if_missing}
					diff_path, _ := os.join_path({dir,mat.diffuse_texname}, allocator)
					
					diff_img, read_err := image.load_from_file(diff_path, img_options)
					if read_err == .Unable_To_Read_File {
						files, folder_err := os.read_directory_by_path(dir, 0, allocator)
						if folder_err != os.General_Error.None {
							continue
						}
						str := strings.to_upper_snake_case(mat.diffuse_texname)
						read_err : image.Error
						for f in files {
							str_entry := strings.to_upper_snake_case(f.name)
							if str_entry == str {
								diff_img, read_err = image.load_from_file(f.fullpath, img_options)
								break
							}
						}
						if read_err != image.General_Image_Error.None {
							continue
						}
					}
					
					tex := new(hxa.Node, allocator)
					
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
					};
					tex.meta_data = make([]hxa.Meta, 1)
					
					tex.meta_data[0] = {
						name = "type",
						value = "texture"
					}
					append(&nodes, tex^)
				}
				
				out.nodes = nodes[:]
				// out.nodes[0] = model_node^
				// for i in 0..<nodes_total {
				// 	out.nodes[i+1] = image_list[i]
				// }
				
				// out.internal_node_count = u32le(len(out.nodes))
				// delete_dynamic_array(nodes)

				// print(obj.attrib.texcoords)
				// print(uv_lencur, uv_len)
				return
			case ".gltf", ".glb":
				data, err := gltf.load_from_file(path)
				defer gltf.unload(data)

			
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
	}

	return
}
/*
*/
main :: proc () {
	readobj_time,
	conversion_time,
	read_time   				 : time.Time
	readobj_duration,
	conversion_duration,
	read_duration   		 : time.Duration

	if len(os.args) == 1 {
		print("[ERROR] No specified model file path")
		os.exit(1)
	}
	model_path := os.args[1]
	
	readobj_time = time.now()
	{
		dir, ext := os.dir(model_path), os.ext(model_path)
		data, err := os.read_entire_file(model_path, context.allocator); defer delete(data)
		obj_load := tinyobj.parse_obj(string(data), dir, tinyobj.FLAG_TRIANGULATE)
	}
	readobj_duration = time.diff(readobj_time, time.now())


	conversion_time = time.now()
	modelhxa := modelConverter_hxa(model_path, context.allocator);
	modelhxa.magic_number = hxa.MAGIC_NUMBER
	modelhxa.version = hxa.LATEST_VERSION

	out_path := recursive_make_folder("models_out", model_path)
	out_file := strings.join(
		{	
			out_path, 
				os.Path_Separator_String, 
			os.base(model_path[:len(model_path) - len(os.long_ext(model_path))]),
				".hxa"
		},
		sep="")
	
	write_err := hxa.write_to_file(out_file, modelhxa)
	
	conversion_duration	= time.diff(conversion_time, time.now())
	
	read_time = time.now()
	out_read, read_err := hxa.read_from_file(out_file, true)
	read_duration	= time.diff(read_time, time.now())


	print("-- Obj Read --")
	print("Duration:", readobj_duration, "\n", sep="")
	// print(modelhxa.nodes[0].content.(hxa.Node_Geometry).vertex_stack[0].data.([]f32le))

	print("-- Conversion --")
	print("Duration:", conversion_duration,", Status: ", write_err, "\n", sep="")

	print("-- Read --")
	print_verify(out_read)
	print("Duration:", read_duration, ", Status: ", read_err, sep="")
	
	
	// print(out_read.nodes[0].content)
	// print(out_read.nodes[0].content.(hxa.Node_Geometry).edge_corner_count,
	// 	len(out_read.nodes[0].content.(hxa.Node_Geometry).corner_stack[0].data.([]i32le))
	// )
}

print_verify :: proc(f: hxa.File) {
	print("Node Length:",len(f.nodes))
	print("Internal Node Count:",f.internal_node_count)
}


recursive_make_folder :: proc(path_out, path: string, alloc := context.temp_allocator) -> string {
	path_split, _ := strings.split_after_n(os.dir(path), os.Path_Separator_String, 2, alloc)
	path_split[0] = path_out
	out := strings.join(path_split, os.Path_Separator_String)
	os.make_directory_all(out)
	return out
}
