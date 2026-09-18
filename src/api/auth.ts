import type express from "express";
import { z } from "zod";
import { supabase } from "../db/supabase.js";
import { env } from "../config/env.js";

// Schemas
export const googleAuthSchema = z.object({
  idToken: z.string().min(1, "ID token es requerido"),
  email: z.string().email("Email inválido"),
  name: z.string().min(1, "Nombre requerido"),
  picture: z.string().url("URL de imagen inválida").optional(),
});

export const setRoleSchema = z.object({
  role: z.enum(["buyer", "seller"], {
    errorMap: () => ({ message: "Role debe ser 'buyer' o 'seller'" }),
  }),
});

export const updateProfileSchema = z.object({
  name: z.string().min(1).max(255).optional(),
  phone: z.string().max(20).optional(),
  store_name: z.string().max(255).optional(),
  store_location: z.string().max(500).optional(),
});

type GoogleAuthInput = z.infer<typeof googleAuthSchema>;
type SetRoleInput = z.infer<typeof setRoleSchema>;
type UpdateProfileInput = z.infer<typeof updateProfileSchema>;

const GOOGLE_TOKENINFO_URL =
  "https://oauth2.googleapis.com/tokeninfo?id_token=";

interface GoogleIdTokenPayload {
  aud: string;
  email: string;
  email_verified: string;
  name: string;
  picture?: string;
  sub: string;
}

async function verifyGoogleIdToken(
  idToken: string,
): Promise<GoogleIdTokenPayload> {
  const response = await fetch(
    `${GOOGLE_TOKENINFO_URL}${encodeURIComponent(idToken)}`,
  );
  if (!response.ok) {
    throw new Error("ID token inválido o expirado.");
  }

  const payload = (await response.json()) as GoogleIdTokenPayload;

  if (payload.aud !== env.GOOGLE_CLIENT_ID) {
    throw new Error("El ID token no coincide con el client ID de Google.");
  }

  if (payload.email_verified !== "true") {
    throw new Error("El email de Google no está verificado.");
  }

  return payload;
}

async function findUserByEmail(email: string) {
  const normalizedEmail = email.trim().toLowerCase();

  for (let page = 1; ; page += 1) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) throw error;

    const user = data.users.find(
      (candidate) => candidate.email?.toLowerCase() === normalizedEmail,
    );
    if (user || data.users.length < 1000) return user ?? null;
  }
}

async function requireAuthenticatedUserId(
  request: express.Request,
  response: express.Response,
): Promise<string | null> {
  const authorization = request.header("authorization")?.trim() ?? "";
  const [scheme, token] = authorization.split(/\s+/, 2);
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    sendAuthError(response, 401, "UNAUTHORIZED", "Bearer token requerido");
    return null;
  }

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) {
    sendAuthError(response, 401, "UNAUTHORIZED", "Sesión inválida o expirada");
    return null;
  }

  return data.user.id;
}

export async function authenticateGoogleUser(
  googleAuth: GoogleAuthInput,
  response: express.Response,
) {
  try {
    const payload = await verifyGoogleIdToken(googleAuth.idToken);

    if (payload.email !== googleAuth.email) {
      return sendAuthError(
        response,
        400,
        "EMAIL_MISMATCH",
        "El correo del token no coincide.",
      );
    }

    const existingUser = await findUserByEmail(googleAuth.email);

    let userId: string;
    let isNewUser = false;

    if (!existingUser) {
      const { data: newUser, error: createError } =
        await supabase.auth.admin.createUser({
          email: googleAuth.email,
          email_confirm: true,
          user_metadata: {
            name: googleAuth.name,
            picture: googleAuth.picture,
            provider: "google",
            google_sub: payload.sub,
          },
        });

      if (createError || !newUser.user) {
        return sendAuthError(
          response,
          500,
          "USER_CREATION_FAILED",
          createError?.message ?? "No se pudo crear el usuario",
        );
      }

      userId = newUser.user.id;
      isNewUser = true;
    } else {
      userId = existingUser.id;
    }

    const { error: profileError } = await supabase.from("user_profiles").upsert(
      {
        id: userId,
        email: googleAuth.email,
        name: googleAuth.name,
        picture: googleAuth.picture,
        provider: "google",
        google_sub: payload.sub,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "id" },
    );

    if (profileError) {
      return sendAuthError(
        response,
        500,
        "PROFILE_CREATION_FAILED",
        profileError.message,
      );
    }

    const { data: profileRow, error: profileRowError } = await supabase
      .from("user_profiles")
      .select("role")
      .eq("id", userId)
      .single();

    if (profileRowError) {
      return sendAuthError(
        response,
        500,
        "PROFILE_READ_FAILED",
        profileRowError.message,
      );
    }

    sendSuccess(response, {
      success: true,
      user: {
        id: userId,
        email: googleAuth.email,
        name: googleAuth.name,
        picture: googleAuth.picture,
        role: profileRow?.role as string | null,
        isNewUser,
      },
    });
  } catch (error) {
    sendAuthError(response, 500, "AUTH_ERROR", String(error));
  }
}

export async function setUserRole(
  userId: string,
  roleData: SetRoleInput,
  response: express.Response,
) {
  try {
    const { error } = await supabase
      .from("user_profiles")
      .update({
        role: roleData.role,
        role_set_at: new Date().toISOString(),
      })
      .eq("id", userId);

    if (error) {
      return sendAuthError(response, 500, "ROLE_UPDATE_FAILED", error.message);
    }

    sendSuccess(response, {
      success: true,
      role: roleData.role,
      message: `Rol establecido como ${roleData.role === "buyer" ? "comprador" : "vendedor"}`,
    });
  } catch (error) {
    sendAuthError(response, 500, "ROLE_ERROR", String(error));
  }
}

export async function getUserProfile(
  userId: string,
  response: express.Response,
) {
  try {
    const { data: profile, error } = await supabase
      .from("user_profiles")
      .select("*")
      .eq("id", userId)
      .single();

    if (error) {
      return sendAuthError(response, 404, "PROFILE_NOT_FOUND", error.message);
    }

    sendSuccess(response, {
      user: profile,
    });
  } catch (error) {
    sendAuthError(response, 500, "PROFILE_ERROR", String(error));
  }
}

export async function updateUserProfile(
  userId: string,
  profileData: UpdateProfileInput,
  response: express.Response,
) {
  try {
    const updateData: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };

    if (profileData.name) updateData.name = profileData.name;
    if (profileData.phone) updateData.phone = profileData.phone;
    if (profileData.store_name) updateData.store_name = profileData.store_name;
    if (profileData.store_location)
      updateData.store_location = profileData.store_location;

    const { error } = await supabase
      .from("user_profiles")
      .update(updateData)
      .eq("id", userId);

    if (error) {
      return sendAuthError(
        response,
        500,
        "PROFILE_UPDATE_FAILED",
        error.message,
      );
    }

    sendSuccess(response, {
      success: true,
      message: "Perfil actualizado correctamente",
    });
  } catch (error) {
    sendAuthError(response, 500, "UPDATE_ERROR", String(error));
  }
}

// Utilidades
function sendSuccess(
  response: express.Response,
  data: unknown,
  meta?: Record<string, unknown>,
) {
  response.status(200).json({
    success: true,
    data,
    ...(meta && { meta }),
  });
}

function sendAuthError(
  response: express.Response,
  status: number,
  code: string,
  message: string,
) {
  response.status(status).json({
    success: false,
    error: {
      code,
      message,
    },
  });
}

export function registerAuthRoutes(app: express.Express) {
  // POST /api/v1/auth/login/google
  app.post("/api/v1/auth/login/google", async (request, response) => {
    try {
      const body = googleAuthSchema.parse(request.body);
      await authenticateGoogleUser(body, response);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return sendAuthError(
          response,
          400,
          "VALIDATION_ERROR",
          error.errors[0]?.message || "Datos inválidos",
        );
      }
      sendAuthError(response, 500, "AUTH_ERROR", String(error));
    }
  });

  // POST /api/v1/auth/role
  app.post("/api/v1/auth/role", async (request, response) => {
    try {
      const userId = await requireAuthenticatedUserId(request, response);
      if (!userId) return;

      const body = setRoleSchema.parse(request.body);
      await setUserRole(userId, body, response);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return sendAuthError(
          response,
          400,
          "VALIDATION_ERROR",
          error.errors[0]?.message || "Datos inválidos",
        );
      }
      sendAuthError(response, 500, "ROLE_ERROR", String(error));
    }
  });

  // GET /api/v1/auth/profile
  app.get("/api/v1/auth/profile", async (request, response) => {
    try {
      const userId = await requireAuthenticatedUserId(request, response);
      if (!userId) return;

      await getUserProfile(userId, response);
    } catch (error) {
      sendAuthError(response, 500, "PROFILE_ERROR", String(error));
    }
  });

  // PATCH /api/v1/auth/profile
  app.patch("/api/v1/auth/profile", async (request, response) => {
    try {
      const userId = await requireAuthenticatedUserId(request, response);
      if (!userId) return;

      const body = updateProfileSchema.parse(request.body);
      await updateUserProfile(userId, body, response);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return sendAuthError(
          response,
          400,
          "VALIDATION_ERROR",
          error.errors[0]?.message || "Datos inválidos",
        );
      }
      sendAuthError(response, 500, "UPDATE_ERROR", String(error));
    }
  });
}
