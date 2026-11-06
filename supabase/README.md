# Supabase — رِواء الحرمين

المشروع الإنتاجي: **`zyfrdlqjmuapkvhrdihn`** (منطقة eu-north-1).

> هذا المجلد هيكل جاهز للربط. **المخطط الفعلي (SQL) ووظيفة Edge لم تُسحب بعد** لأن المشروع
> خارج صلاحية تكامل MCP في هذه الجلسة، ولم يُقدَّم Personal Access Token.
> `BACKEND_CONTRACT.md` (في جذر المستودع) يوثّق الجداول والدوال والوظائف المستخرَجة من الواجهة.

## استعادة المخطط والوظائف الفعلية (على جهازك)
```bash
supabase login
supabase link --project-ref zyfrdlqjmuapkvhrdihn
# مخطط قاعدة البيانات:
supabase db dump -f supabase/migrations/0001_init_schema.sql --schema public
# الأدوار/السياسات (اختياري):
supabase db dump -f supabase/migrations/0002_policies.sql --role-only
# وظيفة Edge:
supabase functions download oto-operation
```
بعدها احذف هذا السطر التوضيحي واعمل commit للملفات المسحوبة.
