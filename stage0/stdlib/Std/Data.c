// Lean compiler output
// Module: Std.Data
// Imports: Std.Data.DHashMap Std.Data.HashMap Std.Data.HashSet Std.Data.DTreeMap Std.Data.TreeMap Std.Data.TreeSet Std.Data.ExtDHashMap Std.Data.ExtHashMap Std.Data.ExtHashSet Std.Data.ExtDTreeMap Std.Data.ExtTreeMap Std.Data.ExtTreeSet Std.Data.DHashMap.RawLemmas Std.Data.HashMap.RawLemmas Std.Data.HashSet.RawLemmas Std.Data.DTreeMap.Raw Std.Data.TreeMap.Raw Std.Data.TreeSet.Raw Std.Data.Iterators
#include <lean/lean.h>
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wunused-label"
#elif defined(__GNUC__) && !defined(__CLANG__)
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#endif
#ifdef __cplusplus
extern "C" {
#endif
lean_object* initialize_Std_Data_DHashMap(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_HashMap(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_HashSet(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_DTreeMap(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_TreeMap(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_TreeSet(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_ExtDHashMap(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_ExtHashMap(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_ExtHashSet(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_ExtDTreeMap(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_ExtTreeMap(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_ExtTreeSet(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_DHashMap_RawLemmas(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_HashMap_RawLemmas(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_HashSet_RawLemmas(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_DTreeMap_Raw(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_TreeMap_Raw(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_TreeSet_Raw(uint8_t builtin, lean_object*);
lean_object* initialize_Std_Data_Iterators(uint8_t builtin, lean_object*);
static bool _G_initialized = false;
LEAN_EXPORT lean_object* initialize_Std_Data(uint8_t builtin, lean_object* w) {
lean_object * res;
if (_G_initialized) return lean_io_result_mk_ok(lean_box(0));
_G_initialized = true;
res = initialize_Std_Data_DHashMap(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_HashMap(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_HashSet(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_DTreeMap(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_TreeMap(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_TreeSet(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_ExtDHashMap(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_ExtHashMap(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_ExtHashSet(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_ExtDTreeMap(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_ExtTreeMap(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_ExtTreeSet(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_DHashMap_RawLemmas(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_HashMap_RawLemmas(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_HashSet_RawLemmas(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_DTreeMap_Raw(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_TreeMap_Raw(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_TreeSet_Raw(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Std_Data_Iterators(builtin, lean_io_mk_world());
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
return lean_io_result_mk_ok(lean_box(0));
}
#ifdef __cplusplus
}
#endif
