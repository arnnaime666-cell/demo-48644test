import { expect, test } from '@playwright/test';
import {
  canAccessSessionRoom,
  getSessionParticipantRole,
  getSessionRoomWindow,
} from '../../src/domains/sessions/server/video-room';

const baseSession = {
  id: 'session-1',
  tutor_id: 'tutor-1',
  student_id: 'student-1',
  scheduled_at: '2026-06-17T15:00:00.000Z',
  duration_minutes: 60,
  status: 'confirmed' as const,
  daily_room_url: null,
  daily_room_name: null,
};

test.describe('Sprint 5 video room lifecycle rules', () => {
  test('opens Daily rooms five minutes before start and expires after session grace', () => {
    const window = getSessionRoomWindow(baseSession);

    expect(window.notBefore.toISOString()).toBe('2026-06-17T14:55:00.000Z');
    expect(window.expiresAt.toISOString()).toBe('2026-06-17T17:00:00.000Z');
    expect(window.notBeforeTimestamp).toBe(1781708100);
    expect(window.expiryTimestamp).toBe(1781715600);
  });

  test('allows access only for confirmed or in-progress sessions inside the room window', () => {
    expect(canAccessSessionRoom(baseSession, new Date('2026-06-17T14:54:59.000Z'))).toEqual({
      allowed: false,
      reason: 'Room opens 5 minutes before the session',
    });

    expect(canAccessSessionRoom(baseSession, new Date('2026-06-17T14:55:00.000Z'))).toEqual({
      allowed: true,
      reason: 'Room is open',
    });

    expect(canAccessSessionRoom(
      { ...baseSession, status: 'in_progress' },
      new Date('2026-06-17T16:30:00.000Z')
    )).toEqual({
      allowed: true,
      reason: 'Room is open',
    });

    expect(canAccessSessionRoom(
      { ...baseSession, status: 'pending' },
      new Date('2026-06-17T15:00:00.000Z')
    )).toEqual({
      allowed: false,
      reason: 'Session must be confirmed or in progress',
    });

    expect(canAccessSessionRoom(baseSession, new Date('2026-06-17T17:00:01.000Z'))).toEqual({
      allowed: false,
      reason: 'Room access has expired',
    });
  });

  test('classifies only booked participants as session room members', () => {
    expect(getSessionParticipantRole(baseSession, 'tutor-1')).toBe('tutor');
    expect(getSessionParticipantRole(baseSession, 'student-1')).toBe('student');
    expect(getSessionParticipantRole(baseSession, 'stranger-1')).toBeNull();
  });
});
