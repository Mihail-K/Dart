
module dart.record;

import std.array;
import std.format;

public import std.conv;
public import std.traits;
public import std.variant;

public import mysql.db;

public import dart.query;

/**
 * Table annotation type.
 * Optionally specifies the name of the table.
 **/
struct Table {
    string name;
}

/**
 * Column annotation type.
 * Optionally specifies the name of the column.
 **/
struct Column {
    string name;
}

/**
 * MaxLength annotation type.
 * Specifies the max length of a field.
 *
 * This annotation is only meaningful for types that declare
 * a length property, and for fields of an array type.
 **/
struct MaxLength {
    int maxLength;
}

/**
 * Id annotation type.
 * Indicates that this column is the primary Id.
 **/
enum Id;

/**
 * Nullable annotation type.
 * Indicates that this column may be null.
 **/
enum Nullable;

/**
 * AutoIncrement annotation type.
 * Indicates that this column is auto incremented.
 *
 * This annotation is only meaningful for Id columns,
 * and cannot be assigned to non-numeric types.
 **/
enum AutoIncrement;

/**
 * Exception type produced by record operations.
 **/
class RecordException : Exception {

    /**
     * Constructs a record exception with an error message.
     **/
    this(string message) {
        super(message);
    }

}

/**
 * The record class type.
 **/
class Record(T) {

    /**
     * Identifiers are prefixed with an underscore to prevent collisions.
     **/
    private static {

        /**
         * The name of the corresponding table.
         **/
        string _table;

        /**
         * The name of the primary id column.
         **/
        string _idColumn;

        /**
         * The column info table, for this record type.
         **/
        ColumnInfo[string] _columns;

        /**
         * Mysql database connection.
         **/
        Connection _dbConnection;

        // Mysql-native provides this.
        version(Have_vibe_d) {
            /**
             * Mysql database connection.
             **/
            MysqlDB _db;
        }

    }

    protected static {

        /**
         * Gets a column definition, by name.
         **/
        ColumnInfo _getColumnInfo(string name) {
            return _columns[name];
        }

        /**
         * Adds a column definition to this record.
         **/
        void _addColumnInfo(ColumnInfo ci) {
            _columns[ci.name] = ci;
        }

        /**
         * Gets the name of the Id column.
         **/
        string getIdColumn() {
            return _idColumn;
        }

        /**
         * Gets the name of the table for this record.
         **/
        string getTableName() {
            return _table;
        }

        /**
         * Gets the column list for this record.
         **/
        string[] getColumnNames() {
            return _columns.keys;
        }

        /**
         * Gets a list of column values, for this instance.
         **/
        Variant[] getColumnValues(T)(T instance) {
            Variant[] values;
            foreach(name, info; _columns)
                values ~= info.get(instance);
            return values;
        }

        /**
         * Gets the database connection.
         **/
        Connection getDBConnection() {
            // Mysql-native provides this.
            version(Have_vibe_d) {
                if(_db !is null) {
                    return _db.lockConnection();
                } else if(_dbConnection !is null) {
                    return _dbConnection;
                }
            } else {
                if(_dbConnection !is null) {
                    return _dbConnection;
                }
            }

            // No database connection set.
            throw new RecordException("Record has no database connection.");
        }

        /**
         * Sets the database connection.
         **/
        void setDBConnection(Connection conn) {
            _dbConnection = conn;
        }

        // Mysql-native provides this.
        version(Have_vibe_d) {
            /**
             * Sets the database connection.
             **/
            void setDBConnection(MysqlDB db) {
                _db = db;
            }
        }

        /**
         * Executes a query that produces a result set.
         **/
        ResultSet executeQueryResult(QueryBuilder query) {
            // Get a database connection.
            auto conn = getDBConnection;
            auto command = Command(conn);

            // Prepare the query.
            command.sql = query.build;
            command.prepare;

            // Bind parameters and execute.
            command.bindParameters(query.getParameters);
            return command.execPreparedResult;
        }

        /**
         * Executes a query that doesn't produce a result set.
         **/
        ulong executeQuery(QueryBuilder query) {
            // Get a database connection.
            auto conn = getDBConnection;
            auto command = Command(conn);
            ulong result;

            // Prepare the query.
            command.sql = query.build;
            command.prepare;

            // Bind parameters and execute.
            command.bindParameters(query.getParameters);
            command.execPrepared(result);

            return result;
        }

        /**
         * Gets the query for get() operations.
         **/
        QueryBuilder getQueryForGet(KT)(KT key) {
            SelectBuilder builder = new SelectBuilder()
                    .select(getColumnNames).from(getTableName).limit(1);
            return builder.where(new WhereBuilder().equals(getIdColumn, key));
        }

        /**
         * Gets the query for find() operations.
         **/
        QueryBuilder getQueryForFind(KT)(KT[string] conditions) {
            auto query = appender!string;
            SelectBuilder builder = new SelectBuilder()
                    .select(getColumnNames).from(getTableName);
            formattedWrite(query, "%-(`%s`=?%| AND %)", conditions.keys);
            return builder.where(query.data, conditions.values);
        }

        /**
         * Gets the query for create() operations.
         **/
        QueryBuilder getQueryForCreate(T)(T instance) {
            InsertBuilder builder = new InsertBuilder()
                    .insert(getColumnNames).into(getTableName);

            // Add column values to query.
            foreach(string name; getColumnNames) {
                auto info = _getColumnInfo(name);
                builder.value(info.get(instance));
            }

            return builder;
        }

        /**
         * Gets the query for update() operations.
         **/
        QueryBuilder getQueryForSave(T)(
                T instance, string[] columns = null...) {
            UpdateBuilder builder = new UpdateBuilder()
                    .update(getTableName).limit(1);

            // Check for a columns list.
            if(columns is null) {
                // Include all columns.
                columns = getColumnNames;
            }

            // Set column values in query.
            foreach(string name; columns) {
                auto info = _getColumnInfo(name);
                builder.set(info.name, info.get(instance));
            }

            // Update the record using the primary id.
            Variant id = _getColumnInfo(getIdColumn).get(instance);
            return builder.where(new WhereBuilder().equals(getIdColumn, id));
        }

        /**
         * Gets the query for remove() operations.
         **/
        QueryBuilder getQueryForRemove(T)(T instance) {
            DeleteBuilder builder = new DeleteBuilder()
                    .from(getTableName).limit(1);

            // Delete the record using the primary id.
            Variant id = _getColumnInfo(getIdColumn).get(instance);
            return builder.where(new WhereBuilder().equals(getIdColumn, id));
        }

    }

}

/**
 * Helper function template for create getter delegates.
 **/
static Variant delegate(Object)
        createGetDelegate(T, string member)(ColumnInfo info) {
    // Alias to target member, for type information.
    alias current = Target!(__traits(getMember, T, member));

    // Create the get delegate.
    return delegate(Object local) {
        // Check if null-assignable.
        static if(isAssignable!(typeof(current), typeof(null))) {
            // Check that the value abides by null rules.
            if(info.notNull && !info.autoIncrement &&
                    __traits(getMember, cast(T)(local), member) is null) {
                throw new RecordException("Non-nullable value of " ~
                        member ~ " was null.");
            }
        }

        // Check for a length property.
        static if(__traits(hasMember, typeof(current), "length") ||
                isSomeString!(typeof(current)) || isArray!(typeof(current))) {
            // Check that length doesn't exceed max.
            if(info.maxLength != -1 && __traits(getMember,
                    cast(T)(local), member).length > info.maxLength) {
                throw new RecordException("Value of " ~
                        member ~ " exceeds max length.");
            }
        }

        // Convert value to variant.
        static if(is(typeof(current) == Variant)) {
            return __traits(getMember, cast(T)(local), member);
        } else {
            return Variant(__traits(getMember, cast(T)(local), member));
        }
    };
}

/**
 * Helper function template for create setter delegates.
 **/
static void delegate(Object, Variant)
        createSetDelegate(T, string member)(ColumnInfo local) {
    // Alias to target member, for type information.
    alias current = Target!(__traits(getMember, T, member));

    // Create the set delegate.
    return delegate(Object local, Variant v) {
        // Convert value from variant.
        static if(is(typeof(current) == Variant)) {
            auto value = v;
        } else {
            auto value = v.coerce!(typeof(current));
        }

        __traits(getMember, cast(T)(local), member) = value;
    };
}

/**
 * The ActiveRecord mixin.
 **/
mixin template ActiveRecord(T : Record!RT, RT) {

    static this() {
        // Check if the class defined an override name.
        _table = getTableDefinition!(T);

        int colCount = 0;
        // Search through class members.
        foreach(member; __traits(derivedMembers, T)) {
            static if(__traits(compiles, __traits(getMember, T, member))) {
                alias current = Target!(__traits(getMember, T, member));

                // Check if this is a column.
                static if(isColumn!(T, member)) {
                    // Ensure that this isn't a function.
                    static if(is(typeof(current) == function)) {
                        throw new RecordException("Functions as columns is unsupported.");
                    } else {
                        // Find the column name.
                        string name = getColumnDefinition!(T, member);

                        // Create a column info record.
                        auto info = new ColumnInfo();
                        info.field = member;
                        info.name = name;

                        // Create delegate get and set.
                        info.get = createGetDelegate!(T, member)(info);
                        info.set = createSetDelegate!(T, member)(info);

                        // Populate other fields.
                        foreach(annotation; __traits(getAttributes, current)) {
                            // Check is @Id is present.
                            static if(is(annotation == Id)) {
                                // Check for duplicate Id.
                                if(_idColumn !is null) {
                                    throw new RecordException(T.stringof ~
                                            " already defined an Id column.");
                                }

                                // Save the Id column.
                                _idColumn = info.name;
                                info.isId = true;
                            }
                            // Check if @Nullable is present.
                            static if(is(annotation == Nullable)) {
                                info.notNull = false;
                            }
                            // Check if @AutoIncrement is present.
                            static if(is(annotation == AutoIncrement)) {
                                // Check that this can be auto incremented.
                                static if(!isNumeric!(typeof(current))) {
                                    throw new RecordException("Cannot increment" ~
                                            member ~ " in " ~ T.stringof);
                                }

                                info.autoIncrement = true;
                            }
                            // Check if @MaxLength(int) is present.
                            static if(is(typeof(annotation) == MaxLength)) {
                                info.maxLength = annotation.maxLength;
                            }
                        }

                        // Store the column definition.
                        _addColumnInfo(info);
                        colCount++;
                    }
                }
            }
        }

        // Check is we have an Id.
        if(_idColumn is null) {
            throw new RecordException(T.stringof ~
                    " doesn't define an Id column.");
        }

        // Check if we have any columns.
        if(colCount == 0) {
            throw new RecordException(T.stringof ~
                    " defines no valid columns.");
        }
    }

    /**
     * Gets an object by its primary key.
     **/
    static T get(KT)(KT key) {
        // Get the query for the operation.
        auto query = getQueryForGet(key);

        // Execute the get() query.
        ResultSet result = executeQueryResult(query);

        // Check that we got a result.
        if(result.empty) {
            throw new RecordException("No records found for " ~
                    getTableName ~ " at " ~ to!string(key));
        }

        T instance = new T;
        auto row = result[0];
        // Bind column values to fields.
        foreach(int idx, string name; result.colNames) {
            auto value = row[idx];
            _getColumnInfo(name).set(instance, value);
        }

        // Return the instance.
        return instance;
    }

    /**
     * Finds matching objects, by column values.
     **/
    static T[] find(KT)(KT[string] conditions...) {
        // Get the query for the operation.
        auto query = getQueryForFind(conditions);

        // Execute the find() query.
        ResultSet result = executeQueryResult(query);

        // Check that we got a result.
        if(result.empty) {
            throw new RecordException("No records found for " ~
                    getTableName ~ " at " ~ to!string(conditions));
        }

        T[] array;
        // Create the initial array of elements.
        for(int i = 0; i < result.length; i++) {
            T instance = new T;
            auto row = result[i];

            foreach(int idx, string name; result.colNames) {
                auto value = row[idx];
                _getColumnInfo(name).set(instance, value);
            }

            // Append the object.
            array ~= instance;
        }

        // Return the array.
        return array;
    }

    /**
     * Creates this object in the database, if it does not yet exist.
     **/
    void create() {
        // Get the query for the operation.
        QueryBuilder query = getQueryForCreate(this);

        // Execute the create() query.
        ulong result = executeQuery(query);

        // Check that something was created.
        if(result < 1) {
            throw new RecordException("No records were created for " ~
                    T.stringof ~ " by create().");
        }

        // Update auto increment columns.
        auto info = _getColumnInfo(getIdColumn);
        if(info.autoIncrement) {
            // Fetch the last insert id.
            query = SelectBuilder.lastInsertId;
            ResultSet id = executeQueryResult(query);

            // Update the auto incremented column.
            info.set(this, id[0][0]);
        }
    }

    /**
     * Saves this object to the database, if it already exists.
     * Optionally specifies a list of columns to be updated.
     **/
    void save(string[] names = null...) {
        // Get the query for the operation.
        auto query = getQueryForSave(this, names);

        // Execute the save() query.
        ulong result = executeQuery(query);

        // Check that something was created.
        if(result < 1) {
            throw new RecordException("No records were updated for " ~
                    T.stringof ~ " by save().");
        }
    }

    /**
     * Removes this object from the database, if it already exists.
     **/
    void remove() {
        // Get the query for the operation.
        auto query = getQueryForRemove(this);

        // Execute the remove() query.
        ulong result = executeQuery(query);

        // Check that something was created.
        if(result < 1) {
            throw new RecordException("No records were removed for " ~
                    T.stringof ~ " by remove().");
        }
    }

}

alias Target(alias T) = T;

class ColumnInfo {

    string name;
    string field;

    bool isId = false;
    bool notNull = true;
    bool autoIncrement = false;

    int maxLength = -1;

    /**
    * Gets the value of the field bound to this column.
    **/
    Variant delegate(Object) get;
    /**
    * Sets the value of the field bound to this column.
    **/
    void delegate(Object, Variant) set;

}

/**
 * Checks if a type is a table, and returns the table name.
 **/
static string getTableDefinition(T)() {
    // Search for @Column annotation.
    foreach(annotation; __traits(getAttributes, T)) {
        // Check if @Table is present.
        static if(is(annotation == Table)) {
            return T.stringof;
        }
        // Check if @Table("name") is present.
        static if(is(typeof(annotation) == Table)) {
            return annotation.name;
        }
    }

    // Not found.
    return T.stringof;
}

/**
 * Compile-time helper for finding columns.
 **/
static bool isColumn(T, string member)() {
    // Search for @Column annotation.
    foreach(annotation; __traits(getAttributes,
    __traits(getMember, T, member))) {
        // Check is @Id is present (implicit column).
        static if(is(annotation == Id)) {
            return true;
        }
        // Check if @Column is present.
        static if(is(annotation == Column)) {
            return true;
        }
        // Check if @Column("name") is present.
        static if(is(typeof(annotation) == Column)) {
            return true;
        }
    }

    // Not found.
    return false;
}

/**
 * Determines the name of a column field.
 **/
static string getColumnDefinition(T, string member)() {
    // Search for @Column annotation.
    foreach(annotation; __traits(getAttributes,
            __traits(getMember, T, member))) {
        // Check if @Column is present.
        static if(is(annotation == Column)) {
            return member;
        }
        // Check if @Column("name") is present.
        static if(is(typeof(annotation) == Column)) {
            return annotation.name;
        }
    }

    // Not found.
    return member;
}
