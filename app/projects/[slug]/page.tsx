import { createServerSupabaseClient } from '@/lib/supabase/server'
import { notFound } from 'next/navigation'
import dynamic from 'next/dynamic'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Progress } from '@/components/ui/progress'
import { Button } from '@/components/ui/button'
import ProjectMapClient from '@/components/map/ProjectMapClient'

export default async function ProjectDetailPage({
  params,
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug } = await params
  const supabase = await createServerSupabaseClient()

  // 1. Ambil data utama proyek + funding
  const { data: project } = await supabase
    .from('projects')
    .select(`
      *,
      v_project_funding ( target_amount, confirmed_amount, pending_amount, remaining_target )
    `)
    .eq('slug', slug)
    .single()

  if (!project) {
    notFound()
  }

  const funding = project.v_project_funding?.[0] || { target_amount: 0, confirmed_amount: 0 }
  const progress = funding.target_amount > 0 
    ? Math.min(100, Math.round((funding.confirmed_amount / funding.target_amount) * 100)) 
    : 0

  // 2. Ambil profil nazhir
  const { data: nazhir } = await supabase
    .from('users')
    .select('full_name, organization_name, avatar_url')
    .eq('id', project.nazhir_id)
    .single()

  // 3. Ambil anggaran (budgets)
  const { data: budgets } = await supabase
    .from('budgets')
    .select('*')
    .eq('project_id', project.id)

  // 4. Ambil indikator dampak
  const { data: indicators } = await supabase
    .from('impact_indicators')
    .select('*')
    .eq('project_id', project.id)

  return (
    <div className="container mx-auto p-4 space-y-8 max-w-5xl">
      {/* Header Proyek */}
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <Badge>{project.category}</Badge>
          <Badge variant="outline">{project.status}</Badge>
        </div>
        <h1 className="text-4xl font-extrabold">{project.title}</h1>
        <p className="text-xl text-muted-foreground">{project.summary}</p>
        <p className="text-sm text-muted-foreground flex items-center gap-2">
          Lokasi: {project.province} {project.regency && `- ${project.regency}`}
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Kolom Kiri: Detail & Narasi */}
        <div className="lg:col-span-2 space-y-8">
          <section className="space-y-4">
            <h2 className="text-2xl font-bold">Tentang Proyek</h2>
            <div className="prose max-w-none text-slate-700 whitespace-pre-wrap">
              {project.description}
            </div>
          </section>

          {/* Indikator Dampak */}
          <section className="space-y-4">
            <h2 className="text-2xl font-bold">Target Dampak (Impact)</h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {indicators && indicators.length > 0 ? (
                indicators.map((ind: any) => (
                  <Card key={ind.id}>
                    <CardHeader className="pb-2">
                      <CardTitle className="text-lg">{ind.name}</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="text-3xl font-bold text-green-600">
                        {ind.target_value} <span className="text-sm font-normal text-slate-500">{ind.unit}</span>
                      </div>
                    </CardContent>
                  </Card>
                ))
              ) : (
                <p className="text-muted-foreground text-sm">Belum ada target indikator yang ditetapkan.</p>
              )}
            </div>
          </section>

          {/* Peta Lokasi */}
          <section className="space-y-4">
            <h2 className="text-2xl font-bold">Lokasi Proyek</h2>
            <div className="w-full h-[300px] bg-slate-100 rounded-lg overflow-hidden border">
              <ProjectMapClient projects={[project]} />
            </div>
          </section>
        </div>

        {/* Kolom Kanan: Funding & CTA */}
        <div className="space-y-6">
          <Card className="sticky top-6">
            <CardHeader>
              <CardTitle>Progres Pendanaan</CardTitle>
              <CardDescription>Dana terkonfirmasi langsung ke Nazhir</CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="space-y-2">
                <div className="flex justify-between text-lg font-bold">
                  <span>Terkumpul</span>
                  <span>{progress}%</span>
                </div>
                <Progress value={progress} className="h-2.5" />
                <div className="text-sm text-muted-foreground flex justify-between">
                  <span>Rp {funding.confirmed_amount?.toLocaleString('id-ID')}</span>
                  <span>Target: Rp {funding.target_amount?.toLocaleString('id-ID')}</span>
                </div>
              </div>

              <div className="pt-4 border-t space-y-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-slate-200 flex-shrink-0" />
                  <div>
                    <p className="text-xs text-muted-foreground">Dilaksanakan oleh (Nazhir)</p>
                    <p className="font-medium text-sm">{nazhir?.organization_name || nazhir?.full_name}</p>
                  </div>
                </div>
              </div>
              
              <Button size="lg" className="w-full font-bold text-lg">
                Tunaikan Wakaf
              </Button>
            </CardContent>
          </Card>

          {/* Rencana Anggaran */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Rencana Alokasi Anggaran</CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="space-y-3">
                {budgets && budgets.length > 0 ? (
                  budgets.map((b: any) => (
                    <li key={b.id} className="flex justify-between text-sm border-b pb-2 last:border-0 last:pb-0">
                      <span className="text-slate-600">{b.line_item}</span>
                      <span className="font-medium">Rp {b.planned_amount?.toLocaleString('id-ID')}</span>
                    </li>
                  ))
                ) : (
                  <p className="text-muted-foreground text-sm">Rincian anggaran belum tersedia.</p>
                )}
              </ul>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}
