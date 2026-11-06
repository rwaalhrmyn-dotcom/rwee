import { supabase } from './supabase'

export async function signInWithGoogle(redirectPath = '/customer') {
  const redirectTo = `${window.location.origin}${redirectPath}`
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo, queryParams: { prompt: 'select_account' } },
  })
  if (error) throw error
}
