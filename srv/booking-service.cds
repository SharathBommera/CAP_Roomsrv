using { RoomBooking as db } from '../db/schema';

service BookingService {

    entity Employees as projection on db.Employee;

    entity Bookings as projection on db.Bookings;

    entity Rooms as projection on db.Rooms;

}