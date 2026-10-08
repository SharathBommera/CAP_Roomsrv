namespace RoomBooking;

type status : String enum {
    yes;
    no;
}

entity Employee {
    key empId          : UUID;
        empName        : String(20);
        empDesignation : String(20);
        bookings       : Composition of many Bookings
                            on bookings.employee = $self;
}

entity Bookings {
    key bookingId          : UUID;
        bookingDate        : Date;
        bookingStartTime   : Time;
        bookingEndTime     : Time;

    virtual bookingAvailability : status;

        employee           : Association to Employee;
        room               : Association to Rooms;
}

entity Rooms {
    key roomId          : UUID;
        roomName        : String(20);
        roomCapacity    : Int16;
        projectorStatus : status;
}