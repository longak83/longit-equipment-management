import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const validRoles = new Set(["admin", "editor", "viewer"]);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default;
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Thiếu cấu hình secrets cho Edge Function." }, 500);
  }

  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json({ error: "Cần đăng nhập." }, 401);

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser(token);
  if (callerError || !callerData.user) return json({ error: "Phiên đăng nhập không hợp lệ." }, 401);

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const callerId = callerData.user.id;
  const { data: callerRole, error: roleError } = await adminClient
    .from("user_roles").select("role").eq("user_id", callerId).maybeSingle();
  if (roleError) return json({ error: "Không xác minh được quyền tài khoản." }, 500);
  if (callerRole?.role !== "admin") return json({ error: "Chỉ Admin được quản lý tài khoản." }, 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Nội dung yêu cầu không hợp lệ." }, 400); }
  const action = String(body.action || "");

  async function listAllUsers() {
    const all: any[] = [];
    for (let page = 1; page <= 20; page++) {
      const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) throw error;
      const batch = data.users || [];
      all.push(...batch);
      if (batch.length < 1000) break;
    }
    return all;
  }

  async function writeAudit(recordId: string, actionName: string, afterData: Record<string, unknown>) {
    await adminClient.from("audit_logs").insert({
      actor_id: callerId, table_name: "user_roles", record_id: recordId,
      action: actionName, after_data: afterData,
    });
  }

  try {
    if (action === "list") {
      const users = await listAllUsers();
      const ids = users.map((u) => u.id);
      const [{ data: roles, error: rolesError }, { data: profiles, error: profilesError }] = await Promise.all([
        adminClient.from("user_roles").select("user_id,role,created_at").in("user_id", ids),
        adminClient.from("profiles").select("id,display_name,created_at").in("id", ids),
      ]);
      if (rolesError || profilesError) throw rolesError || profilesError;
      const roleMap = new Map((roles || []).map((r: any) => [r.user_id, r.role]));
      const profileMap = new Map((profiles || []).map((p: any) => [p.id, p]));
      return json({ users: users.map((u) => ({
        id: u.id,
        email: u.email || "",
        username: String(u.user_metadata?.username || ((u.email || "").toLowerCase().endsWith("@longit.local") ? (u.email || "").slice(0, -13) : "")),
        display_name: profileMap.get(u.id)?.display_name || u.user_metadata?.display_name || "",
        role: roleMap.get(u.id) || "viewer",
        disabled: !!(u.banned_until && new Date(u.banned_until).getTime() > Date.now()),
        archived: u.user_metadata?.account_archived === true,
        created_at: u.created_at,
        last_sign_in_at: u.last_sign_in_at || null,
      })) });
    }

    if (action === "create") {
      const displayName = String(body.display_name || "").trim();
      const username = String(body.username || "").trim().toLowerCase();
      const email = `${username}@longit.local`;
      const password = String(body.password || "");
      const role = String(body.role || "editor");
      if (!displayName || displayName.length > 120) return json({ error: "Họ tên là bắt buộc và tối đa 120 ký tự." }, 400);
      if (!/^[a-z0-9._-]{3,32}$/.test(username)) return json({ error: "Tên đăng nhập dài 3–32 ký tự, chỉ gồm chữ không dấu, số, dấu chấm, gạch dưới hoặc gạch ngang." }, 400);
      if (password.length < 8 || password.length > 128) return json({ error: "Mật khẩu ban đầu phải từ 8 đến 128 ký tự." }, 400);
      if (!validRoles.has(role)) return json({ error: "Vai trò không hợp lệ." }, 400);
      const { data: created, error: createError } = await adminClient.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { display_name: displayName, username },
      });
      if (createError || !created.user) return json({ error: createError?.message || "Không tạo được tài khoản." }, 400);
      const id = created.user.id;
      const { error: profileError } = await adminClient.from("profiles").upsert({ id, display_name: displayName });
      const { error: insertRoleError } = await adminClient.from("user_roles").insert({ user_id: id, role });
      if (profileError || insertRoleError) {
        await adminClient.auth.admin.deleteUser(id);
        return json({ error: "Không lưu được hồ sơ/vai trò; tài khoản vừa tạo đã được hoàn tác." }, 500);
      }
      await writeAudit(id, "CREATE_USER", { email, role, display_name: displayName });
      return json({ user: { id, email, username, display_name: displayName, role, disabled: false, archived: false, created_at: created.user.created_at } }, 201);
    }

    const userId = String(body.user_id || "");
    if (!userId) return json({ error: "Thiếu user_id." }, 400);
    if (userId === callerId && ["update_role", "disable", "archive"].includes(action)) {
      return json({ error: "Không thể tự đổi vai trò hoặc vô hiệu hóa chính tài khoản đang đăng nhập." }, 400);
    }

    if (action === "update_user") {
      const displayName = String(body.display_name || "").trim();
      const login = String(body.login || "").trim().toLowerCase();
      if (!displayName || displayName.length > 120) return json({ error: "Họ tên là bắt buộc và tối đa 120 ký tự." }, 400);
      const isEmail = login.includes("@");
      if (isEmail ? !/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(login) : !/^[a-z0-9._-]{3,32}$/.test(login)) {
        return json({ error: "Tên đăng nhập phải dài 3–32 ký tự hoặc nhập email hợp lệ." }, 400);
      }
      const { data: targetResult, error: targetError } = await adminClient.auth.admin.getUserById(userId);
      if (targetError || !targetResult.user) return json({ error: "Không tìm thấy tài khoản." }, 404);
      const target = targetResult.user;
      const email = isEmail ? login : `${login}@longit.local`;
      const allUsers = await listAllUsers();
      if (allUsers.some((u) => u.id !== userId && (u.email || "").toLowerCase() === email)) {
        return json({ error: "Tên đăng nhập/email này đã được sử dụng." }, 409);
      }
      const metadata = { ...(target.user_metadata || {}), display_name: displayName };
      if (isEmail) delete metadata.username;
      else metadata.username = login;
      const { error: authUpdateError } = await adminClient.auth.admin.updateUserById(userId, {
        email, email_confirm: true, user_metadata: metadata,
      });
      if (authUpdateError) return json({ error: authUpdateError.message }, 400);
      const { error: profileError } = await adminClient.from("profiles").upsert({ id: userId, display_name: displayName });
      if (profileError) throw profileError;
      await writeAudit(userId, "UPDATE_USER", { email, login, display_name: displayName });
      return json({ ok: true });
    }

    if (action === "reset_password") {
      const password = String(body.password || "");
      if (password.length < 8 || password.length > 128) return json({ error: "Mật khẩu phải từ 8 đến 128 ký tự." }, 400);
      const { data: targetResult, error: targetError } = await adminClient.auth.admin.getUserById(userId);
      if (targetError || !targetResult.user) return json({ error: "Không tìm thấy tài khoản." }, 404);
      const { error } = await adminClient.auth.admin.updateUserById(userId, { password });
      if (error) return json({ error: error.message }, 400);
      await writeAudit(userId, "RESET_PASSWORD", { reset_by_admin: true });
      return json({ ok: true });
    }

    if (action === "archive" || action === "restore_archive") {
      const { data: targetResult, error: targetError } = await adminClient.auth.admin.getUserById(userId);
      if (targetError || !targetResult.user) return json({ error: "Không tìm thấy tài khoản." }, 404);
      const target = targetResult.user;
      const { data: targetRole, error: targetRoleError } = await adminClient.from("user_roles").select("role").eq("user_id", userId).maybeSingle();
      if (targetRoleError) throw targetRoleError;
      if (action === "archive" && targetRole?.role === "admin") {
        const allUsers = await listAllUsers();
        const activeIds = new Set(allUsers.filter((u) => !u.banned_until || new Date(u.banned_until).getTime() <= Date.now()).map((u) => u.id));
        const { count, error } = await adminClient.from("user_roles").select("*", { count: "exact", head: true }).eq("role", "admin").in("user_id", [...activeIds]);
        if (error) throw error;
        if ((count || 0) <= 1) return json({ error: "Không thể lưu trữ Admin cuối cùng đang hoạt động." }, 400);
      }
      const archived = action === "archive";
      const { error } = await adminClient.auth.admin.updateUserById(userId, {
        ban_duration: archived ? "876000h" : "none",
        user_metadata: { ...(target.user_metadata || {}), account_archived: archived },
      });
      if (error) throw error;
      await writeAudit(userId, archived ? "ARCHIVE_USER" : "RESTORE_ARCHIVED_USER", { archived, role: targetRole?.role || "viewer" });
      return json({ ok: true });
    }

    if (action === "update_role") {
      const role = String(body.role || "");
      if (!validRoles.has(role)) return json({ error: "Vai trò không hợp lệ." }, 400);
      const { data: target, error: targetError } = await adminClient.from("user_roles").select("role").eq("user_id", userId).maybeSingle();
      if (targetError) throw targetError;
      if (!target) return json({ error: "Không tìm thấy vai trò của tài khoản." }, 404);
      if (target.role === "admin" && role !== "admin") {
        const allUsers = await listAllUsers();
        const activeIds = new Set(allUsers.filter((u) => !u.banned_until || new Date(u.banned_until).getTime() <= Date.now()).map((u) => u.id));
        const { count, error } = await adminClient.from("user_roles").select("*", { count: "exact", head: true }).eq("role", "admin").in("user_id", [...activeIds]);
        if (error) throw error;
        if ((count || 0) <= 1) return json({ error: "Không thể hạ quyền Admin cuối cùng đang hoạt động." }, 400);
      }
      const { error } = await adminClient.from("user_roles").update({ role }).eq("user_id", userId);
      if (error) throw error;
      await writeAudit(userId, "UPDATE_ROLE", { role });
      return json({ ok: true });
    }

    if (action === "disable" || action === "enable") {
      const { data: target, error: targetError } = await adminClient.auth.admin.getUserById(userId);
      if (targetError || !target.user) return json({ error: "Không tìm thấy tài khoản." }, 404);
      const { data: targetRole, error: targetRoleError } = await adminClient.from("user_roles").select("role").eq("user_id", userId).maybeSingle();
      if (targetRoleError) throw targetRoleError;
      if (action === "disable" && targetRole?.role === "admin") {
        const allUsers = await listAllUsers();
        const activeIds = new Set(allUsers.filter((u) => !u.banned_until || new Date(u.banned_until).getTime() <= Date.now()).map((u) => u.id));
        const { count, error } = await adminClient.from("user_roles").select("*", { count: "exact", head: true }).eq("role", "admin").in("user_id", [...activeIds]);
        if (error) throw error;
        if ((count || 0) <= 1) return json({ error: "Không thể vô hiệu hóa Admin cuối cùng đang hoạt động." }, 400);
      }
      const { error } = await adminClient.auth.admin.updateUserById(userId, {
        ban_duration: action === "disable" ? "876000h" : "none",
      });
      if (error) throw error;
      await writeAudit(userId, action === "disable" ? "DISABLE_USER" : "ENABLE_USER", { role: targetRole?.role || "viewer" });
      return json({ ok: true });
    }

    return json({ error: "Thao tác không được hỗ trợ." }, 400);
  } catch (error) {
    console.error("admin-users request failed", error instanceof Error ? error.message : "unknown error");
    return json({ error: "Có lỗi khi xử lý tài khoản. Kiểm tra log Edge Function để biết chi tiết." }, 500);
  }
});
