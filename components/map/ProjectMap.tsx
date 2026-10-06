'use client'

import { useEffect, useState } from 'react'
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import L from 'leaflet'
import Link from 'next/link'
import { Button } from '@/components/ui/button'

// Fix for missing marker icons in leaflet with webpack/nextjs
const icon = L.icon({
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  tooltipAnchor: [16, -28],
  shadowSize: [41, 41]
})

export default function ProjectMap({ projects }: { projects: any[] }) {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  if (!mounted) return null

  // Format GeoJSON location to [lat, lng]
  const getCoordinates = (location: any): [number, number] | null => {
    if (!location) return null
    // PostgREST normally returns GeoJSON Point format: { type: 'Point', coordinates: [lng, lat] }
    // Leaflet expects [lat, lng]
    if (typeof location === 'string') {
      try {
        const parsed = JSON.parse(location)
        if (parsed?.coordinates) return [parsed.coordinates[1], parsed.coordinates[0]]
      } catch (e) {
        return null
      }
    }
    if (location?.coordinates) {
       return [location.coordinates[1], location.coordinates[0]]
    }
    return null
  }

  return (
    <MapContainer 
      center={[-0.7893, 113.9213]} // Pusat Indonesia (Kalimantan)
      zoom={5} 
      className="w-full h-full z-0"
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      
      {projects.map(p => {
        const coords = getCoordinates(p.location)
        if (!coords) return null

        const funding = p.v_project_funding?.[0] || { target_amount: 0, confirmed_amount: 0 }
        const progress = funding.target_amount > 0 
          ? Math.min(100, Math.round((funding.confirmed_amount / funding.target_amount) * 100)) 
          : 0

        return (
          <Marker key={p.id} position={coords} icon={icon}>
            <Popup>
              <div className="font-sans">
                <h3 className="font-bold mb-1">{p.title}</h3>
                <p className="text-xs text-slate-500 mb-2">{p.category}</p>
                <div className="mb-2">
                  <div className="w-full bg-slate-200 rounded-full h-1.5 mb-1">
                    <div className="bg-primary h-1.5 rounded-full" style={{ width: `${progress}%` }}></div>
                  </div>
                  <p className="text-xs">{progress}% Terkumpul</p>
                </div>
                <Link href={`/projects/${p.slug}`}>
                  <Button size="sm" className="w-full mt-2 h-7 text-xs">Detail Proyek</Button>
                </Link>
              </div>
            </Popup>
          </Marker>
        )
      })}
    </MapContainer>
  )
}
